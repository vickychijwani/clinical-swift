import Foundation
import Testing

@testable import clinical_swift

struct AppointmentStatusTests {
    @Test func statusTransitionMatrix() throws {
        try Appointment.Status.scheduled.validateTransition(to: .completed)
        try Appointment.Status.scheduled.validateTransition(to: .cancelled)

        for status in [
            Appointment.Status.scheduled,
            .completed,
            .cancelled,
        ] {
            try status.validateTransition(to: status)
        }

        #expect(
            throws: AppointmentStatusTransitionError.invalidTransition(
                current: .completed,
                requested: .scheduled
            )
        ) {
            try Appointment.Status.completed.validateTransition(to: .scheduled)
        }
        #expect(
            throws: AppointmentStatusTransitionError.invalidTransition(
                current: .completed,
                requested: .cancelled
            )
        ) {
            try Appointment.Status.completed.validateTransition(to: .cancelled)
        }
        #expect(
            throws: AppointmentStatusTransitionError.invalidTransition(
                current: .cancelled,
                requested: .completed
            )
        ) {
            try Appointment.Status.cancelled.validateTransition(to: .completed)
        }
        #expect(
            throws: AppointmentStatusTransitionError.invalidTransition(
                current: .cancelled,
                requested: .scheduled
            )
        ) {
            try Appointment.Status.cancelled.validateTransition(to: .scheduled)
        }
    }

    @Test func draftIsRejectedByTransitionsAndPersistenceConstruction() {
        #expect(throws: AppointmentStatusTransitionError.transientStatus) {
            try Appointment.Status.draft.validateTransition(to: .draft)
        }
        #expect(throws: AppointmentStatusTransitionError.transientStatus) {
            try Appointment.Status.scheduled.validateTransition(to: .draft)
        }
        #expect(throws: AppointmentStatusTransitionError.transientStatus) {
            try Appointment.Status.draft.validateTransition(to: .scheduled)
        }
        #expect(throws: AppointmentStatusTransitionError.transientStatus) {
            try AppointmentRecord.persisted(
                id: UUID(),
                patientID: UUID(),
                start: Date(timeIntervalSinceReferenceDate: 1_000),
                durationMinutes: 30,
                status: .draft,
                createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
                updatedAt: Date(timeIntervalSinceReferenceDate: 1_000)
            )
        }
    }
}
