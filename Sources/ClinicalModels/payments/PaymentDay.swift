import Foundation

public nonisolated struct PaymentItem: Identifiable, Equatable, Sendable {
    public let entry: AccountEntry
    public let title: String
    public var id: UUID { entry.id }
    public var isReceipt: Bool { entry.kind == .receipt }

    public init(entry: AccountEntry, patientName: String? = nil) {
        self.entry = entry
        if case .receipt(.patient, _) = entry.details {
            title = PatientDisplayName.resolve(patientName)
        } else {
            title = entry.note?.nilIfBlank ?? entry.category?.paymentTitle ?? "Unknown"
        }
    }

    public var method: String? {
        switch entry.paymentMethod {
        case .cash: "Cash"
        case .upi: "UPI"
        case .card: "Card"
        case .other, nil: nil
        }
    }

    public var amount: String { Self.amount(entry.amount, isReceipt: isReceipt) }

    public static func amount(_ value: Int, isReceipt: Bool) -> String {
        (isReceipt ? "+₹" : "−₹") + value.formatted(.number.locale(Locale(identifier: "en_IN")))
    }
}

public nonisolated struct PaymentDay: Identifiable, Equatable, Sendable {
    public let id: Date
    public let title: String
    public let items: [PaymentItem]
    public let receipts: Int?
    public let expenses: Int?

    public static func sections(from items: [PaymentItem], today: Date) throws -> [Self] {
        let payments = items.filter { [.receipt, .expense].contains($0.entry.kind) }.sorted {
            if $0.entry.entryDate != $1.entry.entryDate {
                return $0.entry.entryDate > $1.entry.entryDate
            }
            if $0.entry.createdDate != $1.entry.createdDate {
                return $0.entry.createdDate > $1.entry.createdDate
            }
            return $0.id.uuidString > $1.id.uuidString
        }
        guard let earliest = payments.last?.entry.entryDate else { return [] }
        let grouped = Dictionary(grouping: payments) { FinancialDate.day($0.entry.entryDate) }
        var date = FinancialDate.day(today)
        var sections: [Self] = []
        while date >= FinancialDate.day(earliest) {
            let rows = grouped[date] ?? []
            if !rows.isEmpty || FinancialDate.calendar.component(.weekday, from: date) != 1 {
                var receipts: Int?
                var expenses: Int?
                for row in rows {
                    try row.entry.validateValues()
                    if row.isReceipt {
                        receipts = try addingMoney(receipts ?? 0, row.entry.amount)
                    } else {
                        expenses = try addingMoney(expenses ?? 0, row.entry.amount)
                    }
                }
                sections.append(
                    Self(
                        id: date, title: title(for: date, today: today), items: rows,
                        receipts: receipts, expenses: expenses))
            }
            guard let previous = FinancialDate.calendar.date(byAdding: .day, value: -1, to: date)
            else { throw AccountEntryError.invalidFields }
            date = previous
        }
        return sections
    }

    public static func title(for date: Date, today: Date) -> String {
        let calendar = FinancialDate.calendar
        let day = FinancialDate.day(date)
        let today = FinancialDate.day(today)
        if day == today { return "Today" }
        if FinancialDate.nextDay(day) == today { return "Yesterday" }
        let format = Date.FormatStyle(
            locale: Locale(identifier: "en_IN"), calendar: calendar, timeZone: calendar.timeZone
        ).weekday(.abbreviated).day().month(.abbreviated)
        if calendar.component(.year, from: day) == calendar.component(.year, from: today) {
            return day.formatted(format)
        }
        return day.formatted(format.year())
    }
}

extension AccountEntry.Category {
    fileprivate var paymentTitle: String {
        switch self {
        case .patientFees: "Patient fees"
        case .externalConsultations: "External consultations"
        case .referralCommissions: "Referral commissions"
        case .otherReceipts: "Other receipts"
        case .rent: "Rent"
        case .staff: "Staff"
        case .consultants: "Consultants"
        case .utilities: "Utilities"
        case .materials: "Materials"
        case .repairsAndMaintenance: "Repairs and maintenance"
        case .otherOperatingCosts: "Other operating costs"
        case .equipmentPurchases: "Equipment purchases"
        case .clinicImprovements: "Clinic improvements"
        }
    }
}
