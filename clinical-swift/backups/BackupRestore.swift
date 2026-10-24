import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import GRDB
import WidgetKit

nonisolated struct BackupRestoreJournal: Codable, Sendable {
    enum Phase: String, Codable, Sendable {
        case prepared, savedOriginal, installed, rollingBack, rolledBack, finalizing
    }
    var phase: Phase
    let recoveryID: UUID
    let originalFiles: [String]
    let manifest: BackupManifest
    let calendarCutoff: Date
    let previousBackupState: BackupState

    func directory(in store: BackupStateStore) -> URL {
        store.directory.appending(path: "restore-" + recoveryID.uuidString)
    }
}

nonisolated extension BackupRestoreJournal {
    private enum CodingKeys: String, CodingKey {
        case phase, recoveryID, originalFiles, manifest, calendarCutoff, previousBackupState
    }

    private enum LegacyCodingKeys: String, CodingKey { case replacementURL }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        phase = try values.decode(Phase.self, forKey: .phase)
        if let recoveryID = try values.decodeIfPresent(UUID.self, forKey: .recoveryID) {
            self.recoveryID = recoveryID
        } else {
            // Resolve old journal files under the current container, never the saved absolute URL.
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let replacement = try legacy.decode(URL.self, forKey: .replacementURL)
            let name = replacement.deletingLastPathComponent().lastPathComponent
            guard name.hasPrefix("restore-"), let id = UUID(uuidString: String(name.dropFirst(8)))
            else { throw BackupError.invalidSnapshot }
            recoveryID = id
        }
        originalFiles = try values.decode([String].self, forKey: .originalFiles)
        manifest = try values.decode(BackupManifest.self, forKey: .manifest)
        calendarCutoff = try values.decode(Date.self, forKey: .calendarCutoff)
        previousBackupState = try values.decode(BackupState.self, forKey: .previousBackupState)
    }
}

/// Invoke only before opening live pools. File coordination also excludes reads in widget processes.
@MainActor
struct BackupRestore {
    @Dependency(\.calendar) private var calendar
    let store: BackupStateStore
    let databaseURL: URL

    var journalURL: URL { store.directory.appending(path: "restore.json") }

    func prepare(
        snapshot: BackupSnapshot, expectedDatasetID: UUID, recoveryDate: Date,
        confirmed: Bool
    ) throws {
        guard confirmed else { throw BackupError.confirmationRequired }
        guard snapshot.manifest.datasetID == expectedDatasetID else {
            throw BackupError.invalidSnapshot
        }
        guard !FileManager.default.fileExists(atPath: journalURL.path(percentEncoded: false)) else {
            throw BackupError.restoreInProgress
        }
        let migrator = databaseMigrator(allowDebugErasure: false)
        try BackupFiles.validate(snapshot, supportedMigrations: migrator.migrations)
        let recoveryID = UUID()
        let recovery = store.directory.appending(path: "restore-" + recoveryID.uuidString)
        try BackupFiles.createDirectory(recovery)
        let replacement = recovery.appending(path: "replacement.db")
        try FileManager.default.copyItem(at: snapshot.databaseURL, to: replacement)
        let cutoff = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -7, to: recoveryDate) ?? recoveryDate)
        let database = try DatabaseQueue(path: replacement.path(percentEncoded: false))
        do {
            try migrator.migrate(database)
            try Self.prepareCalendar(database, cutoff: cutoff)
            try database.close()
        } catch {
            try? database.close()
            throw error
        }
        _ = try BackupFiles.inspect(replacement)
        try BackupFiles.makeDurable(replacement)
        let originals = [
            databaseURL.lastPathComponent, databaseURL.lastPathComponent + "-wal",
            databaseURL.lastPathComponent + "-shm",
        ]
        .filter {
            FileManager.default.fileExists(
                atPath: databaseURL.deletingLastPathComponent().appending(path: $0).path(
                    percentEncoded: false))
        }
        let journal = BackupRestoreJournal(
            phase: .prepared, recoveryID: recoveryID, originalFiles: originals,
            manifest: snapshot.manifest, calendarCutoff: cutoff,
            previousBackupState: try store.load()
        )
        try BackupFiles.save(journal, to: journalURL)
    }

    func installOrResume() throws {
        var journal = try BackupFiles.load(BackupRestoreJournal.self, from: journalURL)
        if journal.phase == .rollingBack {
            try rollBack()
            return
        }
        if journal.phase == .finalizing {
            try finalize(confirmed: true)
            return
        }
        if journal.phase == .installed { return }
        guard journal.phase != .rolledBack else { throw BackupError.restoreInProgress }
        try ClinicalDatabaseAccess.withReplacement(at: databaseURL) {
            let manager = FileManager.default
            let parent = databaseURL.deletingLastPathComponent()
            let recovery = journal.directory(in: store)
            let rollback = recovery.appending(path: "original")
            if journal.phase == .prepared {
                try BackupFiles.createDirectory(rollback)
                // Originals remain untouched until the complete rollback set is durable.
                for name in journal.originalFiles {
                    let saved = rollback.appending(path: name)
                    if manager.fileExists(atPath: saved.path(percentEncoded: false)) {
                        try manager.removeItem(at: saved)
                    }
                    try manager.copyItem(at: parent.appending(path: name), to: saved)
                    try BackupFiles.protect(saved)
                    try BackupFiles.makeDurable(saved)
                }
                journal.phase = .savedOriginal
                try BackupFiles.save(journal, to: journalURL)
            }
            // The installation file is on the live database's filesystem for atomic rename.
            let install = parent.appending(path: "clinical-restore-install.db")
            if manager.fileExists(atPath: install.path(percentEncoded: false)) {
                try manager.removeItem(at: install)
            }
            try manager.copyItem(at: recovery.appending(path: "replacement.db"), to: install)
            try BackupFiles.protect(install)
            try BackupFiles.makeDurable(install)
            for suffix in ["-wal", "-shm"] {
                let url = URL(filePath: databaseURL.path(percentEncoded: false) + suffix)
                if manager.fileExists(atPath: url.path(percentEncoded: false)) {
                    try manager.removeItem(at: url)
                }
            }
            if rename(install.path(percentEncoded: false), databaseURL.path(percentEncoded: false))
                != 0
            {
                throw BackupError.invalidSnapshot
            }
            try BackupFiles.makeDurable(databaseURL)
            var state = BackupState()
            state.restored = true
            state.datasetID = journal.manifest.datasetID
            state.accountID = journal.previousBackupState.accountID
            state.accountEmail = journal.previousBackupState.accountEmail
            state.rootFolderID = journal.previousBackupState.rootFolderID
            // Resolve the restored dataset folder explicitly on the next backup opportunity.
            if journal.previousBackupState.datasetID == state.datasetID {
                state.datasetFolderID = journal.previousBackupState.datasetFolderID
            }
            try store.save(state)
            journal.phase = .installed
            try BackupFiles.save(journal, to: journalURL)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func rollBack() throws {
        var journal = try BackupFiles.load(BackupRestoreJournal.self, from: journalURL)
        guard journal.phase != .finalizing else { throw BackupError.restoreInProgress }
        guard journal.phase != .prepared else {
            try FileManager.default.removeItem(at: journalURL)
            return
        }
        try ClinicalDatabaseAccess.withReplacement(at: databaseURL) {
            // Persist rollback intent before touching the installed file set.
            journal.phase = .rollingBack
            try BackupFiles.save(journal, to: journalURL)
            let manager = FileManager.default
            for suffix in ["", "-wal", "-shm"] {
                let destination = URL(filePath: databaseURL.path(percentEncoded: false) + suffix)
                if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
                    try manager.removeItem(at: destination)
                }
                if journal.originalFiles.contains(destination.lastPathComponent) {
                    try manager.copyItem(
                        at: journal.directory(in: store).appending(path: "original").appending(
                            path: destination.lastPathComponent),
                        to: destination)
                    try BackupFiles.protect(destination)
                    try BackupFiles.makeDurable(destination)
                }
            }
            try store.save(journal.previousBackupState)
            journal.phase = .rolledBack
            try BackupFiles.save(journal, to: journalURL)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func finalize(confirmed: Bool) throws {
        guard confirmed else { throw BackupError.confirmationRequired }
        var journal = try BackupFiles.load(BackupRestoreJournal.self, from: journalURL)
        guard
            journal.phase == .installed || journal.phase == .rolledBack
                || journal.phase == .finalizing
        else {
            throw BackupError.restoreInProgress
        }
        // A restart must finish acceptance, rather than offer rollback after evidence is removed.
        journal.phase = .finalizing
        try BackupFiles.save(journal, to: journalURL)
        let recovery = journal.directory(in: store)
        if FileManager.default.fileExists(atPath: recovery.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: recovery)
        }
        try FileManager.default.removeItem(at: journalURL)
    }

    static func prepareCalendar(_ database: any DatabaseWriter, cutoff: Date) throws {
        try database.write { db in
            // This private table keeps the fixed recovery window across restarts and retries.
            try db.execute(
                sql:
                    "CREATE TABLE IF NOT EXISTS clinicalCalendarRecovery (source TEXT NOT NULL, sourceID TEXT NOT NULL, cutoff TEXT NOT NULL, PRIMARY KEY (source, sourceID)) STRICT"
            )
            try db.execute(sql: "DELETE FROM clinicalCalendarRecovery")
            for (table, key, source) in [
                ("appointmentCalendarSync", "appointmentID", "appointments"),
                ("unavailableTimeCalendarSync", "unavailableTimeID", "unavailableTimes"),
            ] {
                // Keep every historical link and tombstone, but stop excluded pending delivery.
                // Records without saved Calendar work must not enter Calendar during recovery.
                try db.execute(
                    sql: """
                        UPDATE \(table) SET needsSync = CASE
                          WHEN EXISTS (SELECT 1 FROM \(source) s WHERE s.id = \(table).\(key)
                            AND julianday(s.start) + s.durationMinutes / 1440.0 >= julianday(?)) THEN 1
                          WHEN NOT EXISTS (SELECT 1 FROM \(source) s WHERE s.id = \(table).\(key))
                            AND julianday(eventStart) >= julianday(?) THEN 1 ELSE 0 END,
                          revision = revision + 1
                        """, arguments: [cutoff, cutoff])
                try db.execute(
                    sql:
                        "INSERT INTO clinicalCalendarRecovery SELECT ?, \(key), ? FROM \(table) WHERE needsSync = 1",
                    arguments: [table, cutoff])
            }
        }
    }
}
