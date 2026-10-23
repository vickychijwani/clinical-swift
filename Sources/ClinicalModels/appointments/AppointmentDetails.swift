import Foundation

public nonisolated struct AppointmentDetails: Identifiable, Sendable {
    public let appointment: Appointment
    public let patient: Patient

    public var id: Appointment.ID {
        appointment.id
    }

    public init(appointment: Appointment, patient: Patient) {
        self.appointment = appointment
        self.patient = patient
    }
}
