import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

struct AppointmentCalendarSyncPersistenceTests {
    @Test func migrationDoesNotBackfillExistingAppointments() throws {
        let database = try emptyDatabase()
        let migrator = databaseMigrator()
        try migrator.migrate(database, upTo: "Normalize patient phone numbers")
        let fixture = try insertFixture(into: database)

        try migrator.migrate(database)

        let syncRecord = try fetchSyncRecord(fixture.appointmentID, from: database)
        #expect(syncRecord == nil)
    }

    @Test func appointmentChangesQueueWithoutLosingEventLink() throws {
        let database = try migratedDatabase()
        let fixture = try insertFixture(into: database)
        let linkedStart = fixture.start
        try markSynced(
            fixture.appointmentID,
            eventIdentifier: "event-1",
            eventStart: linkedStart,
            in: database
        )

        let rescheduledStart = fixture.start.addingTimeInterval(24 * 60 * 60)
        try database.write { db in
            try AppointmentRecord.find(fixture.appointmentID)
                .update {
                    $0.start = rescheduledStart
                    $0.durationMinutes = 60
                    $0.updatedAt = rescheduledStart
                }
                .execute(db)
        }

        let fetchedSyncRecord = try fetchSyncRecord(fixture.appointmentID, from: database)
        let syncRecord = try #require(fetchedSyncRecord)
        #expect(syncRecord.needsSync)
        #expect(syncRecord.revision == 2)
        #expect(syncRecord.eventIdentifier == "event-1")
        #expect(syncRecord.eventStart == linkedStart)
    }

    @Test func completionDoesNotQueueButCancellationDoes() throws {
        let database = try migratedDatabase()
        let completedFixture = try insertFixture(into: database)
        try markSynced(
            completedFixture.appointmentID,
            eventIdentifier: "completed-event",
            eventStart: completedFixture.start,
            in: database
        )

        try database.write { db in
            try AppointmentRecord.find(completedFixture.appointmentID)
                .update {
                    $0.status = Appointment.Status.completed.rawValue
                    $0.updatedAt = completedFixture.start.addingTimeInterval(60)
                }
                .execute(db)
        }

        let fetchedCompletedSync = try fetchSyncRecord(
            completedFixture.appointmentID,
            from: database
        )
        let completedSync = try #require(fetchedCompletedSync)
        #expect(!completedSync.needsSync)
        #expect(completedSync.revision == 1)

        let cancelledFixture = try insertFixture(into: database)
        try markSynced(
            cancelledFixture.appointmentID,
            eventIdentifier: "cancelled-event",
            eventStart: cancelledFixture.start,
            in: database
        )
        try database.write { db in
            try AppointmentRecord.find(cancelledFixture.appointmentID)
                .update {
                    $0.status = Appointment.Status.cancelled.rawValue
                    $0.updatedAt = cancelledFixture.start.addingTimeInterval(60)
                }
                .execute(db)
        }

        let fetchedCancelledSync = try fetchSyncRecord(
            cancelledFixture.appointmentID,
            from: database
        )
        let cancelledSync = try #require(fetchedCancelledSync)
        #expect(cancelledSync.needsSync)
        #expect(cancelledSync.revision == 2)
        #expect(cancelledSync.eventIdentifier == "cancelled-event")
    }

    @Test func patientChangeQueuesAppointmentsAndCascadeDeletionRetainsLinks() throws {
        let database = try migratedDatabase()
        let fixture = try insertFixture(into: database)
        try markSynced(
            fixture.appointmentID,
            eventIdentifier: "event-1",
            eventStart: fixture.start,
            in: database
        )

        try database.write { db in
            try PatientRecord.find(fixture.patientID)
                .update {
                    $0.name = #bind("Updated Patient")
                    $0.phone = #bind("+919876543210", as: String?.self)
                    $0.updatedAt = fixture.start.addingTimeInterval(60)
                }
                .execute(db)
        }

        let fetchedPatientUpdateSync = try fetchSyncRecord(
            fixture.appointmentID,
            from: database
        )
        let patientUpdateSync = try #require(fetchedPatientUpdateSync)
        #expect(patientUpdateSync.needsSync)
        #expect(patientUpdateSync.eventIdentifier == "event-1")

        try markSynced(
            fixture.appointmentID,
            eventIdentifier: "event-2",
            eventStart: fixture.start,
            in: database
        )
        try database.write { db in
            try PatientRecord.find(fixture.patientID).delete().execute(db)
        }

        let fetchedDeletionSync = try fetchSyncRecord(fixture.appointmentID, from: database)
        let deletionSync = try #require(fetchedDeletionSync)
        #expect(deletionSync.needsSync)
        #expect(deletionSync.eventIdentifier == "event-2")
        #expect(deletionSync.eventStart == fixture.start)
    }

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

    private func insertFixture(
        into database: DatabaseQueue
    ) throws -> AppointmentCalendarSyncFixture {
        let patientID = UUID()
        let appointmentID = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 800_000)

        try database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: patientID,
                    name: "Aarav Mehta",
                    phone: "+919820144532",
                    dob: nil,
                    gender: nil,
                    createdAt: start,
                    updatedAt: start
                )
            }
            .execute(db)

            let appointment = try AppointmentRecord.persisted(
                id: appointmentID,
                patientID: patientID,
                start: start,
                durationMinutes: 30,
                status: .scheduled,
                createdAt: start,
                updatedAt: start
            )
            try AppointmentRecord.insert { appointment }.execute(db)
        }

        return AppointmentCalendarSyncFixture(
            patientID: patientID,
            appointmentID: appointmentID,
            start: start
        )
    }

    private func markSynced(
        _ appointmentID: Appointment.ID,
        eventIdentifier: String,
        eventStart: Date,
        in database: DatabaseQueue
    ) throws {
        try database.write { db in
            try AppointmentCalendarSyncRecord
                .where { $0.appointmentID.eq(appointmentID) }
                .update {
                    $0.eventIdentifier = #bind(eventIdentifier, as: String?.self)
                    $0.eventStart = #bind(eventStart, as: Date?.self)
                    $0.needsSync = false
                }
                .execute(db)
        }
    }

    private func fetchSyncRecord(
        _ appointmentID: Appointment.ID,
        from database: DatabaseQueue
    ) throws -> AppointmentCalendarSyncRecord? {
        try database.read { db in
            try AppointmentCalendarSyncRecord
                .where { $0.appointmentID.eq(appointmentID) }
                .fetchOne(db)
        }
    }
}

private struct AppointmentCalendarSyncFixture {
    let patientID: Patient.ID
    let appointmentID: Appointment.ID
    let start: Date
}
