import Dependencies
import Foundation

nonisolated struct UnavailableTime: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String?
    let start: Date
    let durationMinutes: Int

    init(id: UUID = UUID(), label: String? = nil, start: Date, durationMinutes: Int) {
        self.id = id
        self.label = label?.nilIfBlank
        self.start = start
        self.durationMinutes = durationMinutes
    }

    var displayLabel: String { label ?? "Blocked" }

    var end: Date {
        @Dependency(\.calendar) var calendar
        return end(using: calendar)
    }

    func end(using calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: durationMinutes, to: start) ?? start
    }
}
