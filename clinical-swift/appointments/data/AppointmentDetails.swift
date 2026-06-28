import Foundation

nonisolated struct AppointmentDetails: Identifiable, Sendable {
    let appointment: Appointment
    let patient: Patient

    var id: Appointment.ID {
        appointment.id
    }
}
