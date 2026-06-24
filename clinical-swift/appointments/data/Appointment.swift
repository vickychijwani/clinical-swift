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

    enum Status: String, Sendable {
        case draft  // Never stored in DB; only for previews
        case scheduled
        case completed
        case cancelled
    }
}
