import ClinicalModels
import Foundation
import SQLiteData

public nonisolated struct PaymentDaysRequest: FetchKeyRequest {
    public let today: Date

    public init(today: Date) { self.today = FinancialDate.day(today) }

    public func fetch(_ db: Database) throws -> [PaymentDay] {
        let rows =
            try AccountEntryRecord
            .where {
                $0.kind.in([AccountEntry.Kind.receipt.rawValue, AccountEntry.Kind.expense.rawValue])
            }
            .leftJoin(PatientRecord.all) { $0.patientID.eq($1.id) }
            .select { PaymentSelection.Columns(entry: $0, patientName: $1.name) }
            .fetchAll(db)
        return try PaymentDay.sections(
            from: rows.map {
                PaymentItem(entry: try $0.entry.entry(), patientName: $0.patientName)
            },
            today: today)
    }
}

@Selection
nonisolated private struct PaymentSelection {
    let entry: AccountEntryRecord
    let patientName: String?
}
