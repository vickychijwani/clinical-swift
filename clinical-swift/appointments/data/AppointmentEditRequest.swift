import Foundation

nonisolated struct AppointmentEditRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let details: AppointmentDetails

    var appointmentID: Appointment.ID {
        details.appointment.id
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
