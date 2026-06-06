import Foundation

struct Appointment: Identifiable {
    let id = UUID()

    let patientName: String
    let startTime: Date
    let durationMinutes: Int
    let status: Status

    enum Status {
        case scheduled
        case completed
        case cancelled
    }
}
