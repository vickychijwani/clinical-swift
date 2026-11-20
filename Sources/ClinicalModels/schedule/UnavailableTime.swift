import Foundation

public nonisolated struct UnavailableTime: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let label: String?
    public let start: Date
    public let durationMinutes: Int

    public init(id: UUID = UUID(), label: String? = nil, start: Date, durationMinutes: Int) {
        self.id = id
        self.label = label?.nilIfBlank
        self.start = start
        self.durationMinutes = durationMinutes
    }

    public var displayLabel: String { label ?? "Blocked" }

    public var end: Date {
        end(using: ClinicDate.calendar)
    }

    public func end(using calendar: Calendar = ClinicDate.calendar) -> Date {
        calendar.date(byAdding: .minute, value: durationMinutes, to: start) ?? start
    }
}
