import Foundation

nonisolated enum TimelineItem: Identifiable, Sendable {
    case appointment(Appointment)
    case unavailableTime(UnavailableTime)

    enum ID: Hashable, Sendable {
        case appointment(UUID)
        case unavailableTime(UUID)

        var sortKey: String {
            switch self {
            case .appointment(let id): "appointment-\(id.uuidString)"
            case .unavailableTime(let id): "unavailable-time-\(id.uuidString)"
            }
        }
    }

    var id: ID {
        switch self {
        case .appointment(let value): .appointment(value.id)
        case .unavailableTime(let value): .unavailableTime(value.id)
        }
    }

    var start: Date {
        switch self {
        case .appointment(let value): value.start
        case .unavailableTime(let value): value.start
        }
    }

    var durationMinutes: Int {
        switch self {
        case .appointment(let value): value.durationMinutes
        case .unavailableTime(let value): value.durationMinutes
        }
    }

    func end(using calendar: Calendar) -> Date {
        switch self {
        case .appointment(let value): value.end(using: calendar)
        case .unavailableTime(let value): value.end(using: calendar)
        }
    }

    func widgetURL(using calendar: Calendar) -> URL? {
        switch self {
        case .appointment(let appointment): ClinicalURL.appointment(appointment.id).url
        case .unavailableTime(let block):
            ClinicalURL.schedule(ScheduleDay(date: block.start, calendar: calendar)).url
        }
    }

    static func ordered(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        let lhsEnd = lhs.start.addingTimeInterval(Double(lhs.durationMinutes) * 60)
        let rhsEnd = rhs.start.addingTimeInterval(Double(rhs.durationMinutes) * 60)
        if lhsEnd != rhsEnd { return lhsEnd < rhsEnd }
        return lhs.id.sortKey < rhs.id.sortKey
    }
}
