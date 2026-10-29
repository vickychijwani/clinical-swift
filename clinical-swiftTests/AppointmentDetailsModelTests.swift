import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct AppointmentDetailsModelTests {
    @Test func scheduledAppointmentShowsStatusActionsWithoutChangingStatus() async throws {
        let fixture = try makeFixture(status: .scheduled)

        try await withDependencies {
            $0.defaultDatabase = fixture.database
        } operation: {
            let model = AppointmentDetailsModel(appointmentID: fixture.appointmentID)
            try await model.load()

            #expect(model.showsStatusActions)
        }

        let record = try await fixture.database.read { db in
            try AppointmentRecord.find(fixture.appointmentID).fetchOne(db)
        }
        #expect(record?.status == Appointment.Status.scheduled.rawValue)
    }

    @Test func successfulStatusUpdateUsesInjectedTimestamp() async throws {
        let fixture = try makeFixture(status: .scheduled)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 2_000)

        let didUpdate = await withDependencies {
            $0.defaultDatabase = fixture.database
            $0.date.now = updatedAt
        } operation: {
            let model = AppointmentDetailsModel(appointmentID: fixture.appointmentID)
            return await model.updateStatus(to: .completed)
        }
        let record = try await fixture.database.read { db in
            try AppointmentRecord.find(fixture.appointmentID).fetchOne(db)
        }

        #expect(didUpdate)
        #expect(record?.status == Appointment.Status.completed.rawValue)
        #expect(record?.updatedAt == updatedAt)
    }

    @Test func staleTerminalStatusRefreshesDetailsAndExplainsConflict() async throws {
        let fixture = try makeFixture(status: .scheduled)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 3_000)

        try await withDependencies {
            $0.defaultDatabase = fixture.database
            $0.date.now = updatedAt
        } operation: {
            let model = AppointmentDetailsModel(appointmentID: fixture.appointmentID)
            try await model.load()
            _ = try await fixture.database.updateAppointmentStatus(
                id: fixture.appointmentID,
                to: .completed,
                at: Date(timeIntervalSinceReferenceDate: 2_000)
            )

            let didUpdate = await model.updateStatus(to: .cancelled)

            #expect(!didUpdate)
            #expect(!model.showsStatusActions)
            #expect(model.details?.appointment.status == .completed)
            #expect(model.errorMessage == "This appointment was already completed.")
        }
    }

    @Test func unexpectedPersistenceFailureKeepsAnErrorPrompt() async throws {
        let database = try testDatabase()
        let updatedAt = Date(timeIntervalSinceReferenceDate: 2_000)

        let result = await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = updatedAt
        } operation: {
            let model = AppointmentDetailsModel(
                appointmentID: UUID(),
                statusUpdater: { _, _, _ in
                    throw TestError.failed
                }
            )
            return (await model.updateStatus(to: .completed), model.errorMessage)
        }

        #expect(!result.0)
        #expect(result.1 == "The appointment could not be updated.")
    }

    @Test func duplicateSubmissionIsRejectedWhileFirstWriteIsPending() async throws {
        let database = try testDatabase()
        let gate = StatusUpdateGate()
        let updatedAt = Date(timeIntervalSinceReferenceDate: 2_000)

        let results = await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = updatedAt
        } operation: {
            let model = AppointmentDetailsModel(
                appointmentID: UUID(),
                statusUpdater: { _, _, _ in
                    await gate.wait()
                    return .updated
                }
            )

            let firstUpdate = Task {
                await model.updateStatus(to: .completed)
            }
            while !gate.isWaiting {
                await Task.yield()
            }

            let duplicateDidUpdate = await model.updateStatus(to: .completed)
            gate.resume()
            let firstDidUpdate = await firstUpdate.value
            return (firstDidUpdate, duplicateDidUpdate)
        }

        #expect(results.0)
        #expect(!results.1)
    }

    @Test func terminalAppointmentsHideStatusActions() async throws {
        for status in [Appointment.Status.completed, .cancelled] {
            let fixture = try makeFixture(status: status)

            try await withDependencies {
                $0.defaultDatabase = fixture.database
            } operation: {
                let model = AppointmentDetailsModel(appointmentID: fixture.appointmentID)
                try await model.load()
                #expect(!model.showsStatusActions)
            }
        }
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

    private enum TestError: Error {
        case failed
    }

    private struct Fixture: Sendable {
        let database: DatabaseQueue
        let appointmentID: Appointment.ID
    }

    @MainActor
    private final class StatusUpdateGate {
        private var continuation: CheckedContinuation<Void, Never>?

        var isWaiting: Bool {
            continuation != nil
        }

        func wait() async {
            await withCheckedContinuation { continuation = $0 }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }
}
