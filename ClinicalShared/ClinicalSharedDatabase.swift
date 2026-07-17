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
        var configuration = configuration
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
                    path: coordinatedURL.path(),
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

    static func openReadOnly(
        at databaseURL: URL,
        fileManager: FileManager = .default
    ) throws -> DatabasePool? {
        guard fileManager.fileExists(atPath: databaseURL.path()) else { return nil }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var databasePool: DatabasePool?
        var openingError: Error?

        coordinator.coordinate(
            readingItemAt: databaseURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                var configuration = Configuration()
                configuration.readonly = true
                databasePool = try DatabasePool(
                    path: coordinatedURL.path(),
                    configuration: configuration
                )
            } catch {
                openingError = error
            }
        }

        if let error = openingError ?? coordinationError {
            throw error
        }
        return databasePool
    }
}

nonisolated enum ClinicalSharedDatabaseError: Error, Equatable, Sendable {
    case appGroupUnavailable
    case coordinationProducedNoDatabase
}
