import ClinicalModels
import Foundation
import SQLiteData

@Table("accountEntries")
public nonisolated struct AccountEntryRecord: Identifiable, Sendable {
    public let id: UUID
    public var kind: String
    public var amount: Int
    public var entryDate: Date
    public var patientID: UUID?
    public var appointmentID: UUID?
    public var category: String?
    public var note: String?
    public var paymentMethod: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(_ entry: AccountEntry, updatedAt: Date) {
        self.id = entry.id
        self.kind = entry.kind.rawValue
        self.amount = entry.amount
        self.entryDate = FinancialDate.day(entry.entryDate)
        self.patientID = entry.patientID
        self.appointmentID = entry.appointmentID
        self.category = entry.category?.rawValue
        self.note = entry.note?.nilIfBlank
        self.paymentMethod = entry.paymentMethod?.rawValue
        self.createdAt = entry.createdDate
        self.updatedAt = updatedAt
    }

    public func entry() throws -> AccountEntry {
        guard let kind = AccountEntry.Kind(rawValue: kind) else {
            throw AccountEntryError.invalidStoredValue(kind)
        }
        let category = try category.map { value in
            guard let category = AccountEntry.Category(rawValue: value) else {
                throw AccountEntryError.invalidStoredValue(value)
            }
            return category
        }
        let method = try paymentMethod.map { value in
            guard let method = AccountEntry.PaymentMethod(rawValue: value) else {
                throw AccountEntryError.invalidStoredValue(value)
            }
            return method
        }
        return AccountEntry(
            id: id, kind: kind, amount: amount, entryDate: entryDate,
            createdDate: createdAt, patientID: patientID, appointmentID: appointmentID,
            category: category, note: note, paymentMethod: method)
    }
}

@Table("patientBalances")
public nonisolated struct PatientBalanceRecord: Identifiable, Sendable {
    public let id: UUID
    public var balance: Int
    public var createdAt: Date
    public var updatedAt: Date
}
