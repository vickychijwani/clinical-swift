import Foundation

nonisolated struct AppointmentEditRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let appointmentID: Appointment.ID
}
