import Foundation
import GRDB
import SQLite3

nonisolated enum ClinicalSharedDatabase {
    static let appGroupIdentifier = "group.in.bitehaus.clinical"
    static let filename = "SQLiteData.db"

    static func databaseURL(fileManager: FileManager = .default) throws -> URL {
        guard
            let containerURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        else {
            throw ClinicalSharedDatabaseError.appGroupUnavailable
        }

        return containerURL.appending(path: filename)
    }

    @MainActor
    static func openWriter(
        at databaseURL: URL,
        configuration: Configuration,
        setup: @MainActor (DatabasePool) throws -> Void
    ) throws -> DatabasePool {
        let access = try ClinicalDatabaseAccess(databaseURL: databaseURL)
        var configuration = configuration
        configuration.prepareDatabase { _ in withExtendedLifetime(access) {} }
        // ClinicalApp posts the matching GRDB suspend and resume notifications as its scene phase
        // changes, preventing this writable pool from acquiring locks while the app is suspended.
        configuration.observesSuspensionNotifications = true
        configuration.prepareDatabase { database in
            guard !database.configuration.readonly else { return }

            var persistentWALFlag: CInt = 1
            let resultCode = withUnsafeMutablePointer(to: &persistentWALFlag) { flag in
                sqlite3_file_control(
                    database.sqliteConnection,
                    nil,
                    SQLITE_FCNTL_PERSIST_WAL,
                    flag
                )
            }
            guard resultCode == SQLITE_OK else {
                throw DatabaseError(resultCode: ResultCode(rawValue: resultCode))
            }
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var databasePool: DatabasePool?
        var openingError: Error?

        coordinator.coordinate(
            writingItemAt: databaseURL,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                let openedDatabasePool = try DatabasePool(
                    path: coordinatedURL.path(percentEncoded: false),
                    configuration: configuration
                )
                try setup(openedDatabasePool)
                databasePool = openedDatabasePool
            } catch {
                openingError = error
            }
        }

        if let error = openingError ?? coordinationError {
            throw error
        }
        guard let databasePool else {
            throw ClinicalSharedDatabaseError.coordinationProducedNoDatabase
        }
        return databasePool
    }

    /// Return values only. The read connection closes before file coordination ends.
    static func read<Value>(
        at databaseURL: URL,
        fileManager: FileManager = .default,
        _ fetch: (Database) throws -> Value
    ) throws -> Value? {
        guard fileManager.fileExists(atPath: databaseURL.path(percentEncoded: false)) else {
            return nil
        }

        let access = try ClinicalDatabaseAccess(databaseURL: databaseURL)
        defer { withExtendedLifetime(access) {} }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Value?, any Error>?
        coordinator.coordinate(
            readingItemAt: databaseURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                // Restore can remove the file while this read waits for coordination.
                guard fileManager.fileExists(atPath: coordinatedURL.path(percentEncoded: false))
                else {
                    return nil
                }
                var configuration = Configuration()
                configuration.readonly = true
                let database = try DatabasePool(
                    path: coordinatedURL.path(percentEncoded: false),
                    configuration: configuration
                )
                do {
                    let value = try database.read(fetch)
                    try database.close()
                    return value
                } catch {
                    try? database.close()
                    throw error
                }
            }
        }

        if let coordinationError { throw coordinationError }
        guard let result else { throw ClinicalSharedDatabaseError.coordinationProducedNoDatabase }
        return try result.get()
    }
}

nonisolated enum ClinicalSharedDatabaseError: Error, Equatable, Sendable {
    case appGroupUnavailable
    case coordinationProducedNoDatabase
    case databaseAccessUnavailable
}
