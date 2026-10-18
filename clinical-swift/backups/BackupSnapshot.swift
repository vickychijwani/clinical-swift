import CryptoKit
import Darwin
import Foundation
import GRDB
import Synchronization

nonisolated struct BackupManifest: Codable, Equatable, Sendable {
    let formatVersion: Int
    let datasetID: UUID
    let snapshotID: UUID
    let capturedAt: Date
    let appVersion: String
    let migrations: [String]
    let byteCount: Int
    let sha256: String
}

nonisolated struct BackupSnapshot: Equatable, Sendable {
    let manifest: BackupManifest
    let directory: URL

    var databaseURL: URL { directory.appending(path: "snapshot.db") }
    var manifestURL: URL { directory.appending(path: "snapshot.json") }
}

nonisolated enum BackupError: LocalizedError, Equatable, Sendable {
    case invalidSnapshot
    case unsupportedSchema
    case accountChanged
    case authorizationRequired
    case configurationRequired
    case drive(Int)
    case missingFolder
    case restoreInProgress
    case confirmationRequired

    var errorDescription: String? {
        switch self {
        case .invalidSnapshot: "The backup failed validation."
        case .unsupportedSchema: "This app cannot read the backup schema."
        case .accountChanged: "Connect the original Google account to upload the saved backup."
        case .authorizationRequired: "Connect Google Drive to protect clinic data."
        case .configurationRequired: "Google Drive setup is required for this app build."
        case .drive(401): "Reconnect Google Drive."
        case .drive(403): "Check Google Drive access and available storage, then retry."
        case .drive: "Google Drive is unavailable. The saved backup will retry."
        case .missingFolder: "The backup folder is unavailable. Restore its access, then reconnect."
        case .restoreInProgress: "Finish or roll back the data restore before starting Clinical."
        case .confirmationRequired: "Confirm database replacement before starting the restore."
        }
    }
}

/// Database backup and file validation run away from the main actor.
actor BackupSnapshotWorker {
    func capture(
        database: any DatabaseReader, directory: URL, datasetID: UUID,
        capturedAt: Date, appVersion: String
    ) async throws -> BackupSnapshot {
        let cancelled = CaptureCancellation()
        return try await withTaskCancellationHandler {
            try capture(
                database: database, directory: directory, datasetID: datasetID,
                capturedAt: capturedAt, appVersion: appVersion, cancelled: cancelled)
        } onCancel: {
            cancelled.value.withLock { $0 = true }
        }
    }

    private func capture(
        database: any DatabaseReader, directory: URL, datasetID: UUID,
        capturedAt: Date, appVersion: String, cancelled: CaptureCancellation
    ) throws -> BackupSnapshot {
        try Task.checkCancellation()
        if cancelled.value.withLock({ $0 }) { throw CancellationError() }
        try BackupFiles.createDirectory(directory)
        let snapshotID = UUID()
        let staging = directory.appending(path: snapshotID.uuidString)
        try BackupFiles.createDirectory(staging)
        do {
            let databaseURL = staging.appending(path: "snapshot.db")
            let destination = try DatabaseQueue(path: databaseURL.path(percentEncoded: false))
            // SQLite's backup API includes committed WAL pages in one consistent view.
            try database.backup(to: destination, pagesPerStep: 128) { _ in
                // GRDB invokes this callback on its queue, outside the Swift task context.
                if cancelled.value.withLock({ $0 }) { throw CancellationError() }
            }
            // The snapshot must open read-only without WAL or SHM files.
            try destination.writeWithoutTransaction { db in
                _ = try String.fetchOne(db, sql: "PRAGMA journal_mode = DELETE")
            }
            try destination.close()
            try Task.checkCancellation()
            let migrations = try BackupFiles.inspect(databaseURL)
            let data = try Data(contentsOf: databaseURL, options: .mappedIfSafe)
            let manifest = BackupManifest(
                formatVersion: 1, datasetID: datasetID, snapshotID: snapshotID,
                capturedAt: Date(timeIntervalSince1970: floor(capturedAt.timeIntervalSince1970)),
                appVersion: appVersion, migrations: migrations,
                byteCount: data.count, sha256: BackupFiles.checksum(data)
            )
            let snapshot = BackupSnapshot(manifest: manifest, directory: staging)
            try BackupFiles.save(manifest, to: snapshot.manifestURL)
            try BackupFiles.protect(databaseURL)
            try BackupFiles.makeDurable(databaseURL)
            return snapshot
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private final class CaptureCancellation: Sendable {
        let value = Mutex(false)
    }

    func validate(_ snapshot: BackupSnapshot, supportedMigrations: [String]) throws {
        try BackupFiles.validate(snapshot, supportedMigrations: supportedMigrations)
    }
}

nonisolated enum BackupFiles {
    static func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String($0, radix: 16).leftPaddedHex }.joined()
    }

    static func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try protect(url)
    }

    static func protect(_ url: URL) throws {
        #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path(percentEncoded: false)
            )
        #endif
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    static func save<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
        try protect(url)
        try makeDurable(url)
    }

    static func makeDurable(_ url: URL) throws {
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.synchronize()
        let parent = open(url.deletingLastPathComponent().path(percentEncoded: false), O_RDONLY)
        guard parent >= 0 else { throw BackupError.invalidSnapshot }
        defer { close(parent) }
        guard fsync(parent) == 0 else { throw BackupError.invalidSnapshot }
    }

    static func load<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    static func inspect(_ url: URL) throws -> [String] {
        var configuration = Configuration()
        configuration.readonly = true
        let database = try DatabaseQueue(
            path: url.path(percentEncoded: false), configuration: configuration)
        defer { try? database.close() }
        return try database.read { db in
            guard try String.fetchAll(db, sql: "PRAGMA integrity_check") == ["ok"],
                try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty
            else { throw BackupError.invalidSnapshot }
            return try String.fetchAll(
                db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"
            )
        }
    }

    static func validate(_ snapshot: BackupSnapshot, supportedMigrations: [String]) throws {
        let manifest = try load(BackupManifest.self, from: snapshot.manifestURL)
        let data = try Data(contentsOf: snapshot.databaseURL, options: .mappedIfSafe)
        guard manifest == snapshot.manifest, manifest.formatVersion == 1,
            manifest.byteCount == data.count, manifest.sha256 == checksum(data),
            try inspect(snapshot.databaseURL) == manifest.migrations
        else { throw BackupError.invalidSnapshot }
        guard manifest.migrations == Array(supportedMigrations.prefix(manifest.migrations.count))
        else { throw BackupError.unsupportedSchema }
    }
}

nonisolated extension String {
    fileprivate var leftPaddedHex: String { count == 1 ? "0" + self : self }
}
