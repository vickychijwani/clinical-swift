import ClinicalModels
import Dependencies
import Foundation
import SQLiteData

public nonisolated enum AppointmentCompletionError: Error, Equatable, Sendable {
    case unavailable, notScheduled, patientChanged, multipleCharges, invalidAmount
}

extension DatabaseWriter {
    /// Read ownership and validate the whole ledger change before completing the appointment.
    public nonisolated func completeAppointment(
        id: Appointment.ID, patientID: Patient.ID, amount: Int,
        paymentMethod: AccountEntry.PaymentMethod?
    ) async throws {
        try await write { db in
            @Dependency(\.date.now) var now
            let timestamp = now
            guard let appointment = try AppointmentRecord.find(id).fetchOne(db) else {
                throw AppointmentCompletionError.unavailable
            }
            // Unlike a status-only self-transition, a second completion must never change money.
            guard appointment.status == Appointment.Status.scheduled.rawValue else {
                throw AppointmentCompletionError.notScheduled
            }
            guard appointment.patientID == patientID else {
                throw AppointmentCompletionError.patientChanged
            }
            guard amount >= 0 else { throw AppointmentCompletionError.invalidAmount }
            let charges = try AccountEntryRecord.where { $0.appointmentID.eq(id) }.fetchAll(db)
            guard charges.count <= 1 else { throw AppointmentCompletionError.multipleCharges }

            var batch = AccountEntryBatch()
            if amount > 0 {
                batch.inserts.append(
                    AccountEntry(
                        details: .receipt(
                            source: .patient(patientID), paymentMethod: paymentMethod),
                        amount: amount, entryDate: timestamp, createdDate: timestamp))
                if let record = charges.first {
                    var charge = try record.entry()
                    charge.amount = amount
                    batch.updates.append(charge)
                } else {
                    batch.inserts.append(
                        AccountEntry(
                            details: .charge(patientID: patientID, appointmentID: id),
                            amount: amount, entryDate: timestamp, createdDate: timestamp))
                }
            } else if let charge = charges.first {
                batch.deletes.append(charge.id)
            }
            // Use the same clock for ledger timestamps, date checks, and appointment completion.
            try withDependencies {
                $0.date.now = timestamp
            } operation: {
                try ClinicalPersistence.saveAccountEntries(batch, in: db)
            }
            try AppointmentRecord.find(id).update {
                $0.status = Appointment.Status.completed.rawValue
                $0.updatedAt = timestamp
            }.execute(db)
        }
    }
}
