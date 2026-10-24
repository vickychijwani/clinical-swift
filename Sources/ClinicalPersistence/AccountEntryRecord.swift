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
        let details: AccountEntry.Details
        switch kind {
        case .charge:
            guard let patientID, category == nil, method == nil else {
                throw AccountEntryError.invalidFields
            }
            details = .charge(patientID: patientID, appointmentID: appointmentID)
        case .adjustment:
            guard let patientID, appointmentID == nil, category == nil, method == nil else {
                throw AccountEntryError.invalidFields
            }
            details = .adjustment(patientID: patientID)
        case .receipt:
            guard appointmentID == nil else { throw AccountEntryError.invalidFields }
            let source: AccountEntry.ReceiptSource
            switch (category, patientID) {
            case (.patientFees, .some(let id)): source = .patient(id)
            case (.externalConsultations, nil): source = .externalConsultations
            case (.referralCommissions, nil): source = .referralCommissions
            case (.otherReceipts, nil): source = .otherReceipts
            default: throw AccountEntryError.invalidFields
            }
            details = .receipt(source: source, paymentMethod: method)
        case .expense:
            guard patientID == nil, appointmentID == nil,
                let category,
                let expense = AccountEntry.ExpenseCategory(rawValue: category.rawValue)
            else { throw AccountEntryError.invalidFields }
            details = .expense(category: expense, paymentMethod: method)
        }
        guard entryDate.timeIntervalSinceReferenceDate.isFinite,
            createdAt.timeIntervalSinceReferenceDate.isFinite
        else { throw AccountEntryError.invalidFields }
        let entry = AccountEntry(
            id: id, details: details, amount: amount, entryDate: entryDate,
            createdDate: createdAt, note: note)
        try entry.validateValues()
        return entry
    }
}

@Table("patientBalances")
public nonisolated struct PatientBalanceRecord: Identifiable, Sendable {
    public let id: UUID
    public var balance: Int
    public var createdAt: Date
    public var updatedAt: Date
}
