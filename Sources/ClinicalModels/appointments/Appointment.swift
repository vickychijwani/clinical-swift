import Dependencies
import Foundation

public struct Appointment: Identifiable, Sendable {
    @Dependency(\.calendar) private var calendar

    public let id: UUID
    public let patientName: String
    public let start: Date
    public let durationMinutes: Int
    public let status: Status

    public var end: Date {
        end(using: calendar)
    }

    public func end(using calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: durationMinutes, to: start) ?? start
    }

    public init(
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

    public nonisolated enum Status: String, Sendable {
        case draft  // Never stored in DB; only for previews
        case scheduled
        case completed
        case cancelled

        public init?(storageValue: String) {
            guard let status = Self(rawValue: storageValue), status != .draft else {
                return nil
            }
            self = status
        }

        public var persistedValue: String? {
            self == .draft ? nil : rawValue
        }

        public func validateTransition(to requestedStatus: Status) throws {
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

public nonisolated enum AppointmentStatusTransitionError: Error, Equatable, Sendable {
    case transientStatus
    case invalidTransition(
        current: Appointment.Status,
        requested: Appointment.Status
    )
}
