import Foundation
import SQLiteData

extension DatabaseWriter {
    nonisolated func updateAppointmentStatus(
        id: Appointment.ID,
        to requestedStatus: Appointment.Status,
        at updatedAt: Date
    ) async throws -> AppointmentStatusUpdateResult {
        guard requestedStatus.persistedValue != nil else {
            throw AppointmentStatusUpdateError.transition(.transientStatus)
        }

        return try await write { db in
            guard let record = try AppointmentRecord.find(id).fetchOne(db) else {
                throw AppointmentStatusUpdateError.unavailable
            }
            guard let currentStatus = Appointment.Status(storageValue: record.status) else {
                throw AppointmentStatusUpdateError.invalidStoredStatus(record.status)
            }

            guard currentStatus != requestedStatus else {
                return .unchanged
            }

            do {
                try currentStatus.validateTransition(to: requestedStatus)
            } catch let error as AppointmentStatusTransitionError {
                throw AppointmentStatusUpdateError.transition(error)
            }

            guard let persistedStatus = requestedStatus.persistedValue else {
                throw AppointmentStatusUpdateError.transition(.transientStatus)
            }

            let updatedID =
                try AppointmentRecord
                .where { $0.id.eq(id) }
                .where { $0.status.eq(currentStatus.rawValue) }
                .update {
                    $0.status = persistedStatus
                    $0.updatedAt = updatedAt
                }
                .returning(\.id)
                .fetchOne(db)

            guard updatedID != nil else {
                throw AppointmentStatusUpdateError.unavailable
            }
            return .updated
        }
    }
}
