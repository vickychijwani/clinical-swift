import Foundation
import SQLiteData

@Table("appointments")
nonisolated struct AppointmentRecord: Identifiable, Sendable {
    let id: UUID
    var patientID: PatientRecord.ID
    var startTime: Date
    var durationMinutes: Int
    var status: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        patientID: PatientRecord.ID,
        startTime: Date,
        durationMinutes: Int,
        status: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.patientID = patientID
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Appointment.Status {
    nonisolated init?(storageValue: String) {
        self.init(rawValue: storageValue)
    }

    nonisolated var storageValue: String {
        rawValue
    }
}
