import ClinicalPersistence
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

struct SampleCalendarSyncPersistenceTests {
    #if DEBUG
        @MainActor
        @Test func debugSampleAppointmentsAreNotQueuedForCalendarExport() throws {
            let database = try migratedDatabase()

            try database.seedSampleDataIfNeeded()

            let syncCount = try database.read { db in
                try AppointmentCalendarSyncRecord.count().fetchOne(db) ?? 0
            }
            #expect(syncCount == 0)
        }
    #endif

    private func emptyDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return try DatabaseQueue(configuration: configuration)
    }

    private func migratedDatabase() throws -> DatabaseQueue {
        let database = try emptyDatabase()
        try migrateDatabase(database)
        return database
    }

}
