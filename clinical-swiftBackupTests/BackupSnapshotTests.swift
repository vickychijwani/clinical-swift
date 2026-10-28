import ClinicalPersistence
import Darwin
import Dependencies
import Foundation
import GRDB
import Testing

@testable import clinical_swift

@MainActor
struct BackupSnapshotTests {
    @Test func standaloneSnapshotIncludesEveryFieldAndWAL() async throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appending(path: "source.db")
        let source = try BackupFixture.database(at: sourceURL)
        let expected = try BackupFixture.contents(source)
        #expect(
            FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false) + "-wal"))
        let snapshot = try await BackupSnapshotWorker().capture(
            database: source, directory: directory.appending(path: "pending"),
            datasetID: BackupFixture.datasetID, capturedAt: BackupFixture.capturedAt,
            appVersion: "test")
        try source.close()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                atPath: sourceURL.path(percentEncoded: false) + suffix)
        }
        let independent = directory.appending(path: "independent")
        try FileManager.default.moveItem(at: snapshot.directory, to: independent)
        let moved = BackupSnapshot(manifest: snapshot.manifest, directory: independent)
        try BackupFiles.validate(moved, supportedMigrations: databaseMigrator().migrations)
        var configuration = Configuration()
        configuration.readonly = true
        let backup = try DatabaseQueue(
            path: moved.databaseURL.path(percentEncoded: false), configuration: configuration)
        defer { try? backup.close() }
        #expect(try BackupFixture.contents(backup) == expected)
        #expect(
            !FileManager.default.fileExists(
                atPath: moved.databaseURL.path(percentEncoded: false) + "-wal"))
        #expect(snapshot.manifest.migrations == databaseMigrator().migrations)
    }

    @Test func corruptionAndNewerSchemasAreRejected() async throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try BackupFixture.database(at: directory.appending(path: "source.db"))
        defer { try? source.close() }
        let snapshot = try await BackupSnapshotWorker().capture(
            database: source, directory: directory, datasetID: BackupFixture.datasetID,
            capturedAt: BackupFixture.capturedAt, appVersion: "test")
        #expect(throws: BackupError.unsupportedSchema) {
            try BackupFiles.validate(snapshot, supportedMigrations: [])
        }
        var bytes = try Data(contentsOf: snapshot.databaseURL)
        bytes[100] ^= 1
        try bytes.write(to: snapshot.databaseURL)
        #expect(throws: BackupError.invalidSnapshot) {
            try BackupFiles.validate(snapshot, supportedMigrations: databaseMigrator().migrations)
        }
    }

    @Test func dailyPolicyAndPendingStateSurviveRestart() throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = BackupManifest(
            formatVersion: 1, datasetID: BackupFixture.datasetID, snapshotID: UUID(),
            capturedAt: BackupFixture.capturedAt, appVersion: "test", migrations: [], byteCount: 1,
            sha256: "test")
        var state = BackupState()
        state.accountID = "original"
        state.lastSuccess = manifest
        #expect(!state.needsAttention(at: manifest.capturedAt))
        #expect(state.needsAttention(at: manifest.capturedAt.addingTimeInterval(172800)))
        #expect(!state.isDue(at: manifest.capturedAt.addingTimeInterval(86399)))
        #expect(state.isDue(at: manifest.capturedAt.addingTimeInterval(86400)))
        state.pending = BackupPendingUpload(
            manifest: manifest,
            accountID: "original", databaseFileID: "db-id", manifestFileID: "json-id")
        let store = BackupStateStore(directory: directory)
        try store.save(state)
        let loaded = try store.load()
        #expect(loaded.pending?.databaseFileID == "db-id")
        #expect(loaded.pending?.accountID == "original")
        #expect(loaded.isDue(at: manifest.capturedAt))
        #expect(loaded.needsAttention(at: manifest.capturedAt.addingTimeInterval(172800)))
    }

    @Test(arguments: [false, true])
    func startupWithoutJournalUsesSavedRecoveryState(restored: Bool) throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackupStateStore(directory: directory)
        var state = BackupState()
        state.restored = restored
        try store.save(state)
        let restore = BackupRestore(store: store, databaseURL: directory.appending(path: "live.db"))

        let policy = try restore.prepareForStartup()

        #expect(policy.seedSamples)
        #expect(policy.recoverySafe == restored)
        #expect(policy.allowsBackgroundBackups)
    }

    @Test func startupProtectsDataWhenBackupStateIsUnreadable() throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackupStateStore(directory: directory)
        try Data("invalid state".utf8).write(to: store.stateURL)
        let restore = BackupRestore(store: store, databaseURL: directory.appending(path: "live.db"))

        let policy = try restore.prepareForStartup()

        #expect(policy.recoverySafe)
        #expect(policy.allowsBackgroundBackups)
    }

    @Test func startupStopsWhenRecoveryJournalIsUnreadable() throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let restore = BackupRestore(
            store: BackupStateStore(directory: directory),
            databaseURL: directory.appending(path: "live.db"))
        try Data("invalid journal".utf8).write(to: restore.journalURL)

        #expect(throws: DecodingError.self) { try restore.prepareForStartup() }
    }

    @Test func restoreCanResumeAndRollBackWithoutLosingOriginalRows() async throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try BackupFixture.database(at: directory.appending(path: "source.db"))
        let original = try BackupFixture.contents(source)
        let snapshot = try await BackupSnapshotWorker().capture(
            database: source, directory: directory.appending(path: "snapshots"),
            datasetID: BackupFixture.datasetID, capturedAt: BackupFixture.capturedAt,
            appVersion: "test")
        try source.close()
        let liveURL = directory.appending(path: "live.db")
        let live = try BackupFixture.database(at: liveURL)
        try await live.write { try $0.execute(sql: "UPDATE patients SET name = 'Before restore'") }
        let before = try BackupFixture.contents(live)
        try live.close()
        let store = BackupStateStore(directory: directory.appending(path: "state"))
        try store.save(BackupState())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try withDependencies {
            $0.calendar = calendar
        } operation: {
            let restore = BackupRestore(store: store, databaseURL: liveURL)
            #expect(throws: BackupError.confirmationRequired) {
                try restore.prepare(
                    snapshot: snapshot, expectedDatasetID: BackupFixture.datasetID,
                    recoveryDate: BackupFixture.capturedAt, confirmed: false)
            }
            try restore.prepare(
                snapshot: snapshot, expectedDatasetID: BackupFixture.datasetID,
                recoveryDate: BackupFixture.capturedAt, confirmed: true)
            let installedPolicy = try restore.prepareForStartup()
            #expect(!installedPolicy.seedSamples)
            #expect(installedPolicy.recoverySafe)
            #expect(!installedPolicy.allowsBackgroundBackups)
            let resumedPolicy = try restore.prepareForStartup()
            #expect(resumedPolicy.recoverySafe)
            #expect(!resumedPolicy.allowsBackgroundBackups)
            let restored = try DatabaseQueue(path: liveURL.path(percentEncoded: false))
            let contents = try BackupFixture.contents(restored)
            #expect(contents["patients"] == original["patients"])
            #expect(contents["appointments"] == original["appointments"])
            #expect(contents["accountEntries"] == original["accountEntries"])
            #expect(contents["patientBalances"] == original["patientBalances"])
            let financialState = try restored.read { db in
                (
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM accountEntries"),
                    try Int.fetchOne(
                        db,
                        sql:
                            "SELECT balance FROM patientBalances WHERE id = '10000000-0000-0000-0000-000000000001'"
                    )
                )
            }
            #expect(financialState.0 == 4)
            #expect(financialState.1 == 1000)
            let pending = try restored.read {
                try String.fetchAll(
                    $0,
                    sql:
                        "SELECT appointmentID FROM appointmentCalendarSync WHERE needsSync = 1 ORDER BY appointmentID"
                )
            }
            #expect(
                pending == [
                    "20000000-0000-0000-0000-000000000001", "20000000-0000-0000-0000-000000000003",
                    "40000000-0000-0000-0000-000000000001",
                ])
            let blocks = try restored.read {
                try String.fetchAll(
                    $0,
                    sql:
                        "SELECT unavailableTimeID FROM unavailableTimeCalendarSync WHERE needsSync = 1"
                )
            }
            #expect(blocks == ["30000000-0000-0000-0000-000000000001"])
            try restored.close()
            #expect(try store.load().datasetID == snapshot.manifest.datasetID)
            // Model termination after rollback intent is saved and live replacement starts.
            var interrupted = try BackupFiles.load(
                BackupRestoreJournal.self, from: restore.journalURL)
            interrupted.phase = .rollingBack
            try BackupFiles.save(interrupted, to: restore.journalURL)
            try Data("interrupted rollback".utf8).write(to: liveURL)
            let rollbackPolicy = try restore.prepareForStartup()
            #expect(rollbackPolicy.recoverySafe)
            #expect(!rollbackPolicy.allowsBackgroundBackups)
            let rolledBackPolicy = try restore.prepareForStartup()
            #expect(!rolledBackPolicy.seedSamples)
            #expect(rolledBackPolicy.recoverySafe)
            #expect(!rolledBackPolicy.allowsBackgroundBackups)
            let rolledBack = try DatabaseQueue(path: liveURL.path(percentEncoded: false))
            #expect(try BackupFixture.contents(rolledBack) == before)
            try rolledBack.close()
            var accepting = try BackupFiles.load(
                BackupRestoreJournal.self, from: restore.journalURL)
            accepting.phase = .finalizing
            try BackupFiles.save(accepting, to: restore.journalURL)
            try FileManager.default.removeItem(
                at: accepting.directory(in: store))
            let finalizedPolicy = try restore.prepareForStartup()
            #expect(finalizedPolicy.seedSamples)
            #expect(finalizedPolicy.allowsBackgroundBackups)
            #expect(
                !FileManager.default.fileExists(
                    atPath: restore.journalURL.path(percentEncoded: false)))
        }
    }

    @Test func scopedReadPreventsDatabaseReplacement() throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "source.db")
        let writer = try BackupFixture.database(at: url)
        try writer.close()
        let count = try ClinicalSharedDatabase.read(at: url) { database in
            #expect(throws: ClinicalSharedDatabaseError.databaseAccessUnavailable) {
                try ClinicalDatabaseAccess.withReplacement(at: url) {}
            }
            let count = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM patients")
            return try #require(count)
        }
        #expect(count == 2)
        try ClinicalDatabaseAccess.withReplacement(at: url) {}
    }

    @Test func suspendedWriterHoldsNoFileLockButStillPreventsReplacement() throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "source.db")
        var writer: DatabasePool? = try ClinicalSharedDatabase.openWriter(
            at: url, configuration: Configuration()
        ) { database in
            try database.write { try $0.execute(sql: "CREATE TABLE probe (value INTEGER)") }
        }
        defer { NotificationCenter.default.post(name: Database.resumeNotification, object: nil) }
        try requireNoFileLock(at: url)
        NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
        #expect(throws: DatabaseError.self) {
            try writer?.write { try $0.execute(sql: "INSERT INTO probe VALUES (1)") }
        }
        try requireNoFileLock(at: url)
        #expect(throws: ClinicalSharedDatabaseError.databaseAccessUnavailable) {
            try ClinicalDatabaseAccess.withReplacement(at: url) {}
        }
        NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
        try writer?.write { try $0.execute(sql: "INSERT INTO probe VALUES (1)") }
        try writer?.close()
        writer = nil
        try ClinicalDatabaseAccess.withReplacement(at: url) {}
    }

    @Test func failedReadAndReplacementReleaseAccess() throws {
        enum Failure: Error { case expected }
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "source.db")
        #expect(try ClinicalSharedDatabase.read(at: url) { _ in true } == nil)
        let writer = try BackupFixture.database(at: url)
        try writer.close()
        #expect(throws: Failure.self) {
            try ClinicalSharedDatabase.read(at: url) { _ in throw Failure.expected }
        }
        #expect(throws: Failure.self) {
            try ClinicalDatabaseAccess.withReplacement(at: url) { throw Failure.expected }
        }
        #expect(try ClinicalSharedDatabase.read(at: url) { _ in true } == true)
        try ClinicalDatabaseAccess.withReplacement(at: url) {
            #expect(throws: ClinicalSharedDatabaseError.databaseAccessUnavailable) {
                try ClinicalSharedDatabase.read(at: url) { _ in true }
            }
            #expect(throws: ClinicalSharedDatabaseError.databaseAccessUnavailable) {
                try ClinicalSharedDatabase.openWriter(at: url, configuration: Configuration()) {
                    _ in
                }
            }
        }
    }

    private func requireNoFileLock(at databaseURL: URL) throws {
        // An old lock file can remain after an update. No pool may keep it locked.
        let lockURL = databaseURL.appendingPathExtension("access-lock")
        let descriptor = open(
            lockURL.path(percentEncoded: false), O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
    }

    @Test func savedWorkSurvivesContainerMoves() async throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appending(path: "old app")
        let group = directory.appending(path: "old group")
        try BackupFiles.createDirectory(group)
        let store = BackupStateStore(directory: app.appending(path: "ClinicalBackups"))
        let liveURL = group.appending(path: "live.db")
        let live = try BackupFixture.database(at: liveURL)
        let captured = try BackupFixture.contents(live)
        let snapshot = try await BackupSnapshotWorker().capture(
            database: live, directory: store.directory.appending(path: "pending"),
            datasetID: BackupFixture.datasetID, capturedAt: BackupFixture.capturedAt,
            appVersion: "test")
        try await live.write { try $0.execute(sql: "UPDATE patients SET name = 'Before restore'") }
        let original = try BackupFixture.contents(live)
        try live.close()
        var state = BackupState()
        state.accountID = "original-account"
        state.datasetID = snapshot.manifest.datasetID
        state.pending = BackupPendingUpload(
            manifest: snapshot.manifest, accountID: "original-account",
            databaseFileID: "saved-db-id", manifestFileID: "saved-json-id")
        try store.save(state)
        let restore = BackupRestore(store: store, databaseURL: liveURL)
        try withDependencies {
            $0.calendar = Calendar(identifier: .gregorian)
        } operation: {
            try restore.prepare(
                snapshot: snapshot, expectedDatasetID: BackupFixture.datasetID,
                recoveryDate: BackupFixture.capturedAt, confirmed: true)
        }
        // Neither old container remains available when work resumes.
        let movedApp = directory.appending(path: "moved app")
        let movedGroup = directory.appending(path: "moved group")
        try FileManager.default.moveItem(at: app, to: movedApp)
        try FileManager.default.moveItem(at: group, to: movedGroup)
        let movedStore = BackupStateStore(directory: movedApp.appending(path: "ClinicalBackups"))
        let movedURL = movedGroup.appending(path: "live.db")
        let movedRestore = BackupRestore(store: movedStore, databaseURL: movedURL)
        let pending = try #require(movedStore.load().pending)
        #expect(pending.databaseFileID == "saved-db-id")
        #expect(pending.manifestFileID == "saved-json-id")
        try BackupFiles.validate(
            pending.snapshot(in: movedStore), supportedMigrations: databaseMigrator().migrations)
        _ = try ClinicalSharedDatabase.read(at: movedURL) { _ in
            #expect(throws: ClinicalSharedDatabaseError.databaseAccessUnavailable) {
                try movedRestore.installOrResume()
            }
        }
        try movedRestore.installOrResume()

        // A completed install must permit startup during a widget read.
        _ = try ClinicalSharedDatabase.read(at: movedURL) { database in
            let restored = try BackupFixture.contents(database)
            #expect(restored["patients"] == captured["patients"])
            try movedRestore.installOrResume()
            #expect(try BackupFixture.contents(database) == restored)
        }
        let savedJournal = try String(contentsOf: movedRestore.journalURL, encoding: .utf8)
        #expect(!savedJournal.contains(app.path(percentEncoded: false)))
        #expect(!savedJournal.contains("replacementURL"))
        #expect(!savedJournal.contains("databaseURL"))

        // Rollback also resolves its evidence and previous pending work from the current roots.
        let finalApp = directory.appending(path: "final app")
        let finalGroup = directory.appending(path: "final group")
        try FileManager.default.moveItem(at: movedApp, to: finalApp)
        try FileManager.default.moveItem(at: movedGroup, to: finalGroup)
        let finalStore = BackupStateStore(directory: finalApp.appending(path: "ClinicalBackups"))
        let finalRestore = BackupRestore(
            store: finalStore, databaseURL: finalGroup.appending(path: "live.db"))
        try finalRestore.rollBack()
        let rolledBack = try DatabaseQueue(
            path: finalRestore.databaseURL.path(percentEncoded: false))
        #expect(try BackupFixture.contents(rolledBack) == original)
        try rolledBack.close()
        let previous = try finalStore.load()
        #expect(previous.datasetID == state.datasetID)
        #expect(previous.accountID == state.accountID)
        #expect(previous.pending?.databaseFileID == "saved-db-id")
        try BackupFiles.validate(
            #require(previous.pending).snapshot(in: finalStore),
            supportedMigrations: databaseMigrator().migrations)
        let savedState = try String(contentsOf: finalStore.stateURL, encoding: .utf8)
        #expect(!savedState.contains("directory"))
        let journal = try BackupFiles.load(BackupRestoreJournal.self, from: finalRestore.journalURL)
        try finalRestore.finalize(confirmed: true)
        #expect(
            !FileManager.default.fileExists(
                atPath: finalRestore.journalURL.path(percentEncoded: false)))
        #expect(
            !FileManager.default.fileExists(
                atPath: journal.directory(in: finalStore).path(percentEncoded: false)))
    }
}
