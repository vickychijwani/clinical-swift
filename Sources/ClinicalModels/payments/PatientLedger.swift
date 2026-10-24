import Foundation

public nonisolated struct PatientLedger: Equatable, Sendable {
    public struct Coverage: Equatable, Sendable {
        public let entryID: UUID
        public let appointmentID: UUID?
        public let amount: Int
        public let covered: Int
        public var remaining: Int { amount - covered }
    }

    public let balance: Int
    public let moneyReceived: Int
    public let unallocatedCredit: Int
    /// Includes positive adjustments so patient-level debt takes its place before later charges.
    public let obligations: [Coverage]
    public let charges: [Coverage]

    public init(entries: [AccountEntry], patientID: UUID, through date: Date? = nil) throws {
        let end = date.map(FinancialDate.nextDay) ?? .distantFuture
        let entries = entries.filter {
            $0.patientID == patientID && $0.entryDate < end
        }.sorted {
            if $0.entryDate != $1.entryDate { return $0.entryDate < $1.entryDate }
            if $0.createdDate != $1.createdDate { return $0.createdDate < $1.createdDate }
            return $0.id.uuidString < $1.id.uuidString
        }
        var balance = 0
        var received = 0
        var credit = 0
        for entry in entries {
            guard entry.amount != Int.min, entry.amount != 0,
                entry.kind == .adjustment || entry.amount > 0
            else { throw AccountEntryError.invalidAmount }
            let change = try entry.balanceChange
            balance = try addingMoney(balance, change)
            if entry.kind == .receipt { received = try addingMoney(received, entry.amount) }
            if change < 0 { credit = try addingMoney(credit, -change) }
        }
        var obligations: [Coverage] = []
        var charges: [Coverage] = []
        for entry in entries
        where entry.kind == .charge || (entry.kind == .adjustment && entry.amount > 0) {
            let covered = min(entry.amount, credit)
            credit -= covered
            let coverage = Coverage(
                entryID: entry.id, appointmentID: entry.appointmentID,
                amount: entry.amount, covered: covered)
            obligations.append(coverage)
            if entry.kind == .charge { charges.append(coverage) }
        }
        self.balance = balance
        self.moneyReceived = received
        self.unallocatedCredit = credit
        self.obligations = obligations
        self.charges = charges
    }

    /// Always call this on coverage from the full patient ledger.
    public func appointment(_ id: UUID) throws -> AppointmentCoverage {
        let linked = charges.filter { $0.appointmentID == id }
        return try AppointmentCoverage(
            amount: linked.reduce(0) { try addingMoney($0, $1.amount) },
            covered: linked.reduce(0) { try addingMoney($0, $1.covered) })
    }
}

public nonisolated struct AppointmentCoverage: Equatable, Sendable {
    public let amount: Int
    public let covered: Int
    public var remaining: Int { amount - covered }
}

public nonisolated struct CashFlow: Equatable, Sendable {
    public struct Group: Hashable, Sendable {
        public let category: AccountEntry.Category
        public let paymentMethod: AccountEntry.PaymentMethod?
        public var reportingGroup: AccountEntry.ReportingGroup { category.group }
    }
    public let totals: [Group: Int]
    public let received: Int
    public let paid: Int
    public let net: Int

    public init(entries: [AccountEntry]) throws {
        var totals: [Group: Int] = [:]
        var received = 0
        var paid = 0
        for entry in entries where entry.kind == .receipt || entry.kind == .expense {
            guard entry.amount > 0, let category = entry.category else {
                throw AccountEntryError.invalidFields
            }
            let group = Group(category: category, paymentMethod: entry.paymentMethod)
            totals[group] = try addingMoney(totals[group, default: 0], entry.amount)
            if entry.kind == .receipt {
                received = try addingMoney(received, entry.amount)
            } else {
                paid = try addingMoney(paid, entry.amount)
            }
        }
        self.totals = totals
        self.received = received
        self.paid = paid
        self.net = try addingMoney(received, -paid)
    }

    public func total(for category: AccountEntry.Category) throws -> Int {
        try totals.filter { $0.key.category == category }.values.reduce(0, addingMoney)
    }

    /// A missing method is its own reporting group. It does not mean cash.
    public func amounts(paymentMethod: AccountEntry.PaymentMethod?) throws -> (
        received: Int, paid: Int, net: Int
    ) {
        let matching = totals.filter { $0.key.paymentMethod == paymentMethod }
        let received = try matching.filter { $0.key.reportingGroup == .incoming }.values.reduce(
            0, addingMoney)
        let paid = try matching.filter { $0.key.reportingGroup != .incoming }.values.reduce(
            0, addingMoney)
        return (received, paid, try addingMoney(received, -paid))
    }

    public func total(for group: AccountEntry.ReportingGroup) throws -> Int {
        try totals.filter { $0.key.reportingGroup == group }.values.reduce(0, addingMoney)
    }
}
