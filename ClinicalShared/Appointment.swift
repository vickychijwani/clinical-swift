import Dependencies
import Foundation

nonisolated struct Appointment: Identifiable, Sendable {
    @Dependency(\.calendar) private var calendar

    let id: UUID
    let patientName: String
    let start: Date
    let durationMinutes: Int
    let status: Status

    var end: Date {
        end(using: calendar)
    }

    func end(using calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: durationMinutes, to: start) ?? start
    }

    init(
        id: UUID = UUID(),
        patientName: String,
        start: Date,
        durationMinutes: Int,
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

        init?(storageValue: String) {
            guard let status = Self(rawValue: storageValue), status != .draft else {
                return nil
            }
            self = status
        }

        var persistedValue: String? {
            self == .draft ? nil : rawValue
        }

        func validateTransition(to requestedStatus: Status) throws {
            guard self != .draft, requestedStatus != .draft else {
                throw AppointmentStatusTransitionError.transientStatus
            }

            guard self != requestedStatus else { return }

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
