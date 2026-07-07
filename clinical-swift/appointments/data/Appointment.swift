import Dependencies
import Foundation

nonisolated struct Appointment: Identifiable, Sendable {
    @Dependency(\.calendar) private var calendar

    let id: UUID

    let patientName: String
    let start: Date
    let durationMinutes: Minutes
    let status: Status

    var end: Date {
        calendar.date(byAdding: .minute, value: durationMinutes, to: start)!
    }

    init(
        id: UUID = UUID(),
        patientName: String,
        start: Date,
        durationMinutes: Minutes,
        status: Status
    ) {
        self.id = id
        self.patientName = patientName
        self.start = start
        self.durationMinutes = durationMinutes
        self.status = status
    }

    nonisolated enum Status: String, Sendable {
        case draft  // Never stored in DB; only for previews
        case scheduled
        case completed
        case cancelled

        func validateTransition(to requestedStatus: Status) throws {
            guard self != .draft, requestedStatus != .draft else {
                throw AppointmentStatusTransitionError.transientStatus
            }

            guard self != requestedStatus else {
                return
            }

            guard self == .scheduled,
                requestedStatus == .completed || requestedStatus == .cancelled
            else {
                throw AppointmentStatusTransitionError.invalidTransition(
                    current: self,
                    requested: requestedStatus
                )
            }
        }
    }
}

nonisolated enum AppointmentStatusTransitionError: Error, Equatable, Sendable {
    case transientStatus
    case invalidTransition(
        current: Appointment.Status,
        requested: Appointment.Status
    )
}
