import ClinicalModels
import Dependencies
import Foundation
import SQLiteData

/// All supported local financial mutations share this boundary, including single-entry actions.
public nonisolated struct AccountEntryBatch: Sendable {
    public var inserts: [AccountEntry]
    public var updates: [AccountEntry]
    public var deletes: [UUID]

    public init(inserts: [AccountEntry] = [], updates: [AccountEntry] = [], deletes: [UUID] = []) {
        self.inserts = inserts
        self.updates = updates
        self.deletes = deletes
    }
}

extension DatabaseWriter {
    public nonisolated func saveAccountEntries(_ batch: AccountEntryBatch) async throws {
        try await write { db in try ClinicalPersistence.saveAccountEntries(batch, in: db) }
    }

    public nonisolated func createAccountEntry(_ entry: AccountEntry) async throws {
        try await saveAccountEntries(AccountEntryBatch(inserts: [entry]))
    }

    public nonisolated func editAccountEntry(_ entry: AccountEntry) async throws {
        try await saveAccountEntries(AccountEntryBatch(updates: [entry]))
    }

    public nonisolated func deleteAccountEntry(id: UUID) async throws {
        try await saveAccountEntries(AccountEntryBatch(deletes: [id]))
    }

    public nonisolated func rebuildPatientBalances() async throws {
        try await write { db in try ClinicalPersistence.rebuildPatientBalances(in: db) }
    }

    public nonisolated func correctPatientBalance(
        patientID: UUID, to target: Int, through date: Date, receipt: AccountEntry? = nil
    ) async throws {
        try await write { db in
            try ClinicalPersistence.correctPatientBalance(
                patientID: patientID, to: target, through: date, receipt: receipt, in: db)
        }
    }
}

/// A savepoint also protects callers that catch a failure inside their own write transaction.
public nonisolated func saveAccountEntries(_ batch: AccountEntryBatch, in db: Database) throws {
    try db.inSavepoint {
        @Dependency(\.date.now) var now
        var mutationIDs = Set<UUID>()
        for id in batch.deletes + batch.updates.map(\.id)
            + batch.inserts.filter({ $0.amount != 0 }).map(\.id)
        {
            guard mutationIDs.insert(id).inserted else {
                throw AccountEntryError.duplicateMutation(id)
            }
        }
        var affected = Set<UUID>()
        // Read old ownership before any mutation, including both sides of a patient move.
        for id in batch.deletes + batch.updates.map(\.id) {
            guard let record = try AccountEntryRecord.find(id).fetchOne(db) else {
                throw AccountEntryError.missingEntry(id)
            }
            if let patientID = record.patientID { affected.insert(patientID) }
        }
        for id in batch.deletes {
            try AccountEntryRecord.find(id).delete().execute(db)
        }
        for entry in batch.updates {
            try entry.validate()
            try validateReferences(entry, in: db)
            let record = AccountEntryRecord(entry, updatedAt: now)
            try AccountEntryRecord.find(entry.id).update {
                $0.kind = record.kind
                $0.amount = record.amount
                $0.entryDate = record.entryDate
                $0.patientID = record.patientID
                $0.appointmentID = record.appointmentID
                $0.category = record.category
                $0.note = record.note
                $0.paymentMethod = record.paymentMethod
                $0.updatedAt = record.updatedAt
            }.execute(db)
            if let patientID = entry.patientID { affected.insert(patientID) }
        }
        for entry in batch.inserts where entry.amount != 0 {
            try entry.validate()
            try validateReferences(entry, in: db)
            // Plain INSERT must fail on a duplicate ID. Upsert would overwrite financial history.
            try AccountEntryRecord.insert { AccountEntryRecord(entry, updatedAt: now) }.execute(db)
            if let patientID = entry.patientID { affected.insert(patientID) }
        }
        for patientID in affected {
            if try currentPatientBalance(patientID: patientID, in: db) < 0 {
                throw AccountEntryError.negativeBalance(patientID)
            }
        }
        return .commit
    }
}

nonisolated private func validateReferences(_ entry: AccountEntry, in db: Database) throws {
    if let patientID = entry.patientID, try PatientRecord.find(patientID).fetchOne(db) == nil {
        throw AccountEntryError.missingPatient(patientID)
    }
    if let appointmentID = entry.appointmentID {
        guard let appointment = try AppointmentRecord.find(appointmentID).fetchOne(db) else {
            throw AccountEntryError.missingAppointment(appointmentID)
        }
        guard appointment.patientID == entry.patientID else {
            throw AccountEntryError.appointmentPatientMismatch
        }
    }
}

public nonisolated func validateAppointmentPatientChange(
    id: UUID, patientID: UUID, in db: Database
) throws {
    guard let appointment = try AppointmentRecord.find(id).fetchOne(db) else {
        throw AccountEntryError.missingAppointment(id)
    }
    if appointment.patientID != patientID,
        try AccountEntryRecord.where({ $0.appointmentID.eq(id) }).count().fetchOne(db) != 0
    {
        throw AccountEntryError.appointmentHasCharges
    }
}

/// Replaces summaries; never adds a second copy of the ledger total to an existing summary.
public nonisolated func rebuildPatientBalances(in db: Database) throws {
    try db.inSavepoint {
        try db.execute(
            sql: """
                DELETE FROM patientBalances;
                INSERT INTO patientBalances(id, balance, createdAt, updatedAt)
                SELECT patientID, SUM(CASE WHEN kind = 'receipt' THEN -amount ELSE amount END),
                  strftime('%Y-%m-%d %H:%M:%f','now'), strftime('%Y-%m-%d %H:%M:%f','now')
                FROM accountEntries WHERE patientID IS NOT NULL GROUP BY patientID;
                """)
        return .commit
    }
}

/// Read the dated history inside the transaction, before adding this action's receipt.
public nonisolated func correctPatientBalance(
    patientID: UUID, to target: Int, through date: Date, receipt: AccountEntry? = nil,
    in db: Database
) throws {
    try db.inSavepoint {
        guard target >= 0 else { throw AccountEntryError.negativeTargetBalance }
        guard try PatientRecord.find(patientID).fetchOne(db) != nil else {
            throw AccountEntryError.missingPatient(patientID)
        }
        let date = FinancialDate.day(date)
        guard date <= FinancialDate.today else { throw AccountEntryError.futureDate }
        let ledger = try patientLedger(patientID: patientID, through: date, in: db)
        let (difference, overflow) = target.subtractingReportingOverflow(ledger.balance)
        guard !overflow else { throw AccountEntryError.overflow }
        var entries = [
            AccountEntry(
                kind: .adjustment, amount: difference, entryDate: date, patientID: patientID)
        ]
        if let receipt {
            guard receipt.kind == .receipt, receipt.patientID == patientID else {
                throw AccountEntryError.invalidFields
            }
            entries.append(receipt)
        }
        try saveAccountEntries(AccountEntryBatch(inserts: entries), in: db)
        return .commit
    }
}
