import Foundation

nonisolated struct Appointment: Identifiable, Sendable {
    let id: UUID

    let patientName: String
    let startTime: Date
    let durationMinutes: Minutes
    let status: Status

    init(
        id: UUID = UUID(),
        patientName: String,
        startTime: Date,
        durationMinutes: Minutes,
        status: Status
    ) {
        self.id = id
        self.patientName = patientName
        self.startTime = startTime
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
