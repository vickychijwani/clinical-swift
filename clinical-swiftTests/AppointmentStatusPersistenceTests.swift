import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

struct AppointmentStatusPersistenceTests {
    @Test func statusUpdateAdvancesTimestampAndSelfTransitionIsIdempotent() async throws {
        let fixture = try makeFixture(status: .scheduled)
        let completedAt = Date(timeIntervalSinceReferenceDate: 2_000)
        let repeatedAt = Date(timeIntervalSinceReferenceDate: 3_000)

        let updateResult = try await fixture.database.updateAppointmentStatus(
            id: fixture.appointmentID,
            to: .completed,
            at: completedAt
        )
        let unchangedResult = try await fixture.database.updateAppointmentStatus(
            id: fixture.appointmentID,
            to: .completed,
            at: repeatedAt
        )
        let record = try await fixture.database.read { db in
            try AppointmentRecord.find(fixture.appointmentID).fetchOne(db)
        }

        #expect(updateResult == .updated)
        #expect(unchangedResult == .unchanged)
        #expect(record?.status == Appointment.Status.completed.rawValue)
        #expect(record?.updatedAt == completedAt)
    }

    @Test func terminalTransitionAndDraftRequestAreRejected() async throws {
        let fixture = try makeFixture(status: .completed)

        await #expect(
            throws: AppointmentStatusUpdateError.transition(
                .invalidTransition(current: .completed, requested: .cancelled)
            )
        ) {
            try await fixture.database.updateAppointmentStatus(
                id: fixture.appointmentID,
                to: .cancelled,
                at: Date(timeIntervalSinceReferenceDate: 2_000)
            )
        }
        await #expect(throws: AppointmentStatusUpdateError.transition(.transientStatus)) {
            try await fixture.database.updateAppointmentStatus(
                id: fixture.appointmentID,
                to: .draft,
                at: Date(timeIntervalSinceReferenceDate: 2_000)
            )
        }
    }

    @Test func missingAndInvalidStoredAppointmentsAreDistinguished() async throws {
        let fixture = try makeFixture(status: .scheduled)
        let missingID = UUID()

        await #expect(throws: AppointmentStatusUpdateError.unavailable) {
            try await fixture.database.updateAppointmentStatus(
                id: missingID,
                to: .completed,
                at: Date(timeIntervalSinceReferenceDate: 2_000)
            )
        }

        try await fixture.database.write { db in
            try db.execute(sql: "UPDATE appointments SET status = 'unexpected'")
        }
        await #expect(throws: AppointmentStatusUpdateError.invalidStoredStatus("unexpected")) {
            try await fixture.database.updateAppointmentStatus(
                id: fixture.appointmentID,
                to: .completed,
                at: Date(timeIntervalSinceReferenceDate: 2_000)
            )
        }
    }

    @Test func competingTerminalUpdatesCannotOverwriteEachOther() async throws {
        let fixture = try makeFixture(status: .scheduled)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 2_000)

        let completionTask = Task {
            try await fixture.database.updateAppointmentStatus(
                id: fixture.appointmentID,
                to: .completed,
                at: updatedAt
            )
        }
        let cancellationTask = Task {
            try await fixture.database.updateAppointmentStatus(
                id: fixture.appointmentID,
                to: .cancelled,
                at: updatedAt
            )
        }

        let results = await [completionTask.result, cancellationTask.result]
        let successCount = results.reduce(into: 0) { count, result in
            if case .success = result {
                count += 1
            }
        }
        let record = try await fixture.database.read { db in
            try AppointmentRecord.find(fixture.appointmentID).fetchOne(db)
        }

        #expect(successCount == 1)
        #expect(
            record?.status == Appointment.Status.completed.rawValue
                || record?.status == Appointment.Status.cancelled.rawValue
        )
    }

    @Test func normalQueriesExcludeCancelledAndNextAppointmentUsesScheduledOnly() throws {
        let database = try testDatabase()
        let patientID = UUID()
        let selectedDate = Date(timeIntervalSinceReferenceDate: 10_000).startOfDay()
        let now = selectedDate.setTime(9, 0)
        let completedID = UUID()
        let cancelledID = UUID()
        let scheduledID = UUID()
        let completedStart = selectedDate.setTime(10, 0)
        let cancelledStart = selectedDate.setTime(11, 0)
        let scheduledStart = selectedDate.setTime(12, 0)

        try database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: patientID,
                    name: "Aarav Mehta",
                    phone: nil,
                    dob: nil,
                    gender: nil,
                    createdAt: now,
                    updatedAt: now
                )
            }
            .execute(db)

            for (id, start, status) in [
                (completedID, completedStart, Appointment.Status.completed),
                (cancelledID, cancelledStart, .cancelled),
                (scheduledID, scheduledStart, .scheduled),
            ] {
                let record = try AppointmentRecord.persisted(
                    id: id,
                    patientID: patientID,
                    start: start,
                    durationMinutes: 30,
                    status: status,
                    createdAt: now,
                    updatedAt: now
                )
                try AppointmentRecord.insert { record }.execute(db)
            }
        }

        let scheduleRows = try database.read { db in
            try querySchedule(selectedDate: selectedDate).fetchAll(db)
        }
        let cancelledDetails = try database.read { db in
            try appointmentDetailsQuery(id: cancelledID).fetchOne(db)
        }
        let patientRow = try database.read { db in
            try patientDetailsQuery(id: patientID, now: now).fetchOne(db)
        }
        let retainedCancelledRecord = try database.read { db in
            try AppointmentRecord.find(cancelledID).fetchOne(db)
        }

        #expect(Set(scheduleRows.map(\.id)) == Set([completedID, scheduledID]))
        #expect(cancelledDetails == nil)
        #expect(patientRow?.details.nextAppointmentDate == scheduledStart)
        #expect(retainedCancelledRecord?.status == Appointment.Status.cancelled.rawValue)
    }

    private func makeFixture(status: Appointment.Status) throws -> Fixture {
        let database = try testDatabase()
        let patientID = UUID()
        let appointmentID = UUID()
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let record = try AppointmentRecord.persisted(
            id: appointmentID,
            patientID: patientID,
            start: now,
            durationMinutes: 30,
            status: status,
            createdAt: now,
            updatedAt: now
        )

        try database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: patientID,
                    name: "Aarav Mehta",
                    phone: nil,
                    dob: nil,
                    gender: nil,
                    createdAt: now,
                    updatedAt: now
                )
            }
            .execute(db)
            try AppointmentRecord.insert { record }.execute(db)
        }

        return Fixture(database: database, appointmentID: appointmentID)
    }

    private func testDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: configuration)
        try migrateDatabase(database)
        return database
    }

    private struct Fixture: Sendable {
        let database: DatabaseQueue
        let appointmentID: Appointment.ID
    }
}
