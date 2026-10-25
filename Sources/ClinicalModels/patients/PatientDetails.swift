import Foundation

public nonisolated struct PatientDetails: Identifiable, Hashable, Sendable {
    public let patient: Patient
    public let nextAppointmentDate: Date?
    public let currentBalance: Int

    public var id: Patient.ID {
        patient.id
    }

    public init(patient: Patient, nextAppointmentDate: Date?, currentBalance: Int = 0) {
        self.patient = patient
        self.nextAppointmentDate = nextAppointmentDate
        self.currentBalance = currentBalance
    }
}
