import Foundation
import SQLiteData

@Table("appointments")
nonisolated struct AppointmentRecord: Identifiable, Sendable {
    let id: UUID
    var patientID: PatientRecord.ID
    var start: Date
    var durationMinutes: Int
    var status: String
    var createdAt: Date
    var updatedAt: Date

    private init(
        id: UUID,
        patientID: PatientRecord.ID,
        start: Date,
        durationMinutes: Int,
        status: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.patientID = patientID
        self.start = start
        self.durationMinutes = durationMinutes
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func persisted(
        id: UUID,
        patientID: PatientRecord.ID,
        start: Date,
        durationMinutes: Int,
        status: Appointment.Status,
        createdAt: Date,
        updatedAt: Date
    ) throws -> Self {
        guard let status = status.persistedValue else {
            throw AppointmentStatusTransitionError.transientStatus
        }

        return Self(
            id: id,
            patientID: patientID,
            start: start,
            durationMinutes: durationMinutes,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func appointment(patientName: String) -> Appointment? {
        guard let status = Appointment.Status(storageValue: status) else {
            return nil
        }

        return Appointment(
            id: id,
            patientName: patientName,
            start: start,
            durationMinutes: durationMinutes,
            status: status
        )
    }
}
