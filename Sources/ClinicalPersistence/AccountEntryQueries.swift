import ClinicalModels
import Foundation
import SQLiteData

/// Requests return domain values and can be used directly with SQLiteData's @Fetch.
public nonisolated struct AccountHistoryRequest: FetchKeyRequest {
    public let patientID: UUID
    public let through: Date?

    public init(patientID: UUID, through: Date? = nil) {
        self.patientID = patientID
        self.through = through.map(FinancialDate.day)
    }

    public func fetch(_ db: Database) throws -> [AccountEntry] {
        try patientEntriesQuery(patientID, through: through).fetchAll(db).map { try $0.entry() }
    }
}

nonisolated private func patientEntriesQuery(_ patientID: UUID, through: Date?)
    -> some Statement<AccountEntryRecord> & Sendable
{
    let end = through.map(FinancialDate.nextDay) ?? .distantFuture
    return AccountEntryRecord.where { $0.patientID.eq(patientID) }
        .where { $0.entryDate < end }
        .order { ($0.entryDate.asc(), $0.createdAt.asc(), $0.id.asc()) }
        .select { $0 }
}

public nonisolated struct PatientLedgerRequest: FetchKeyRequest {
    public let patientID: UUID
    public let through: Date?
    public init(patientID: UUID, through: Date? = nil) {
        self.patientID = patientID
        self.through = through.map(FinancialDate.day)
    }
    public func fetch(_ db: Database) throws -> PatientLedger {
        try patientLedger(patientID: patientID, through: through, in: db)
    }
}

public nonisolated func patientLedger(patientID: UUID, through: Date? = nil, in db: Database) throws
    -> PatientLedger
{
    try PatientLedger(
        entries: AccountHistoryRequest(patientID: patientID, through: through).fetch(db),
        patientID: patientID)
}

public nonisolated struct AppointmentChargesRequest: FetchKeyRequest {
    public let appointmentID: UUID
    public init(appointmentID: UUID) { self.appointmentID = appointmentID }
    public func fetch(_ db: Database) throws -> [AccountEntry] {
        try AccountEntryRecord.where { $0.appointmentID.eq(appointmentID) }
            .order { ($0.entryDate.asc(), $0.createdAt.asc(), $0.id.asc()) }
            .fetchAll(db).map { try $0.entry() }
    }
}

public nonisolated struct AppointmentCoverageRequest: FetchKeyRequest {
    public let appointmentID: UUID
    public let through: Date?
    public init(appointmentID: UUID, through: Date? = nil) {
        self.appointmentID = appointmentID
        self.through = through.map(FinancialDate.day)
    }
    public func fetch(_ db: Database) throws -> AppointmentCoverage {
        guard let appointment = try AppointmentRecord.find(appointmentID).fetchOne(db) else {
            throw AccountEntryError.missingAppointment(appointmentID)
        }
        return try patientLedger(patientID: appointment.patientID, through: through, in: db)
            .appointment(appointmentID)
    }
}

public nonisolated struct CurrentPatientBalanceRequest: FetchKeyRequest {
    public let patientID: UUID
    public init(patientID: UUID) { self.patientID = patientID }
    public func fetch(_ db: Database) throws -> Int {
        try currentPatientBalance(patientID: patientID, in: db)
    }
}

public nonisolated func currentPatientBalance(patientID: UUID, in db: Database) throws -> Int {
    try PatientBalanceRecord.find(patientID).fetchOne(db)?.balance ?? 0
}

public nonisolated struct PatientAccountsRequest: FetchKeyRequest {
    public let now: Date
    public let owingOnly: Bool
    public init(now: Date, owingOnly: Bool = false) {
        self.now = now
        self.owingOnly = owingOnly
    }
    public func fetch(_ db: Database) throws -> [PatientDetails] {
        if owingOnly {
            // Filter the joined summary in SQL. One summary row cannot multiply appointment aggregates.
            return try patientListRowsQuery(now: now, owingOnly: true).fetchAll(db).map(\.details)
        }
        return try patientListRowsQuery(now: now).fetchAll(db).map(\.details)
    }
}

public nonisolated struct OutstandingBalanceRequest: FetchKeyRequest {
    public init() {}
    public func fetch(_ db: Database) throws -> Int {
        try PatientBalanceRecord.where { $0.balance > 0 }.select { $0.balance.sum().ifnull(0) }
            .fetchOne(db) ?? 0
    }
}

/// Boundaries are clinic days: start is included and end is excluded.
public nonisolated struct CashFlowRequest: FetchKeyRequest {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) {
        self.start = FinancialDate.day(start)
        self.end = FinancialDate.day(end)
    }
    public func fetch(_ db: Database) throws -> CashFlow {
        // Decode every dated row before selecting cash movements. An unknown kind must not disappear from a report.
        let entries = try AccountEntryRecord.where { $0.entryDate >= start && $0.entryDate < end }
            .fetchAll(db).map { try $0.entry() }
        return try CashFlow(entries: entries)
    }
}

public nonisolated struct PreviousAccountNotesRequest: FetchKeyRequest {
    public let category: AccountEntry.Category
    public init(category: AccountEntry.Category) { self.category = category }
    public func fetch(_ db: Database) throws -> [String] {
        let records = try AccountEntryRecord.where { $0.category.eq(category.rawValue) }
            .order { ($0.entryDate.desc(), $0.createdAt.desc(), $0.id.desc()) }.fetchAll(db)
        var seen = Set<String>()
        return records.compactMap { record in
            guard let note = record.note?.nilIfBlank, seen.insert(note).inserted else { return nil }
            return note
        }
    }
}
