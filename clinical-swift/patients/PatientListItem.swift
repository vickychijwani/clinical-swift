import Foundation

nonisolated struct PatientListItem: Identifiable, Hashable, Sendable {
    let patient: Patient
    let nextAppointmentDate: Date?

    var id: Patient.ID {
        patient.id
    }
}
