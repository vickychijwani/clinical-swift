import Foundation

nonisolated struct PatientDetails: Identifiable, Hashable, Sendable {
    let patient: Patient
    let nextAppointmentDate: Date?

    var id: Patient.ID {
        patient.id
    }
}
