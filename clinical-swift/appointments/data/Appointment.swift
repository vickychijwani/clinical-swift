import Foundation

nonisolated struct Appointment: Identifiable, Sendable {
    let id: UUID

    let patientName: String
    let startTime: Date
    let durationMinutes: Int
    let status: Status

    init(
        id: UUID = UUID(),
        patientName: String,
        startTime: Date,
        durationMinutes: Int,
        status: Status
    ) {
        self.id = id
        self.patientName = patientName
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.status = status
    }

    enum Status: String, Sendable {
        case scheduled
        case completed
        case cancelled
    }
}
