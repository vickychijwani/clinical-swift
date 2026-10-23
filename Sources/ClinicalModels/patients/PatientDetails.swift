import Foundation

public nonisolated struct PatientDetails: Identifiable, Hashable, Sendable {
    public let patient: Patient
    public let nextAppointmentDate: Date?

    public var id: Patient.ID {
        patient.id
    }

    public init(patient: Patient, nextAppointmentDate: Date?) {
        self.patient = patient
        self.nextAppointmentDate = nextAppointmentDate
    }
}
