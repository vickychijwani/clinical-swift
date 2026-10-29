import ClinicalPersistence
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

struct SampleCalendarSyncPersistenceTests {
    #if DEBUG
        @MainActor
        @Test func debugSamplesExistWithoutQueuedCalendarDelivery() throws {
            let database = try migratedDatabase()

            try database.seedSampleDataIfNeeded()

            let counts = try database.read { db in
                (
                    appointments: try AppointmentRecord.count().fetchOne(db) ?? 0,
                    blocks: try UnavailableTimeRecord.count().fetchOne(db) ?? 0,
                    appointmentDelivery: try AppointmentCalendarSyncRecord.count().fetchOne(db),
                    blockDelivery: try UnavailableTimeCalendarSyncRecord.count().fetchOne(db)
                )
            }
            #expect(counts.appointments > 0)
            #expect(counts.blocks > 0)
            #expect(counts.appointmentDelivery == 0)
            #expect(counts.blockDelivery == 0)
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
