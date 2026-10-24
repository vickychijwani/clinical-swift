import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

nonisolated enum PaymentsFixture {
    static let now = try! Date("2026-10-24T12:00:00Z", strategy: .iso8601)
    static let earlier = try! Date("2026-10-19T12:00:00Z", strategy: .iso8601)
    static let patientID = UUID()
    static let otherPatientID = UUID()
    static let appointmentID = UUID()

    static func entry(_ kind: AccountEntry.Kind, _ amount: Int, date: Date = now) -> AccountEntry {
        AccountEntry(
            kind: kind, amount: amount, entryDate: date, createdDate: now,
            patientID: kind == .expense ? nil : patientID,
            category: kind == .receipt ? .patientFees : (kind == .expense ? .rent : nil))
    }

    static func database() throws -> DatabaseQueue {
        let database = try DatabaseQueue(configuration: clinicalDatabaseConfiguration())
        try migrateDatabase(database)
        try database.write { db in
            for id in [patientID, otherPatientID] {
                try PatientRecord.insert {
                    PatientRecord(
                        id: id, name: "Patient", phone: nil, dob: nil,
                        gender: nil, createdAt: now, updatedAt: now)
                }.execute(db)
            }
            let appointment = try AppointmentRecord.persisted(
                id: appointmentID, patientID: patientID,
                start: now, durationMinutes: 30, status: .scheduled, createdAt: now, updatedAt: now)
            try AppointmentRecord.insert { appointment }.execute(db)
        }
        return database
    }

    static func run(_ operation: (DatabaseQueue) throws -> Void) throws {
        try withDependencies {
            $0.date.now = now
        } operation: {
            try operation(database())
        }
    }

    static func save(_ entries: [AccountEntry], in db: Database) throws {
        try saveAccountEntries(AccountEntryBatch(inserts: entries), in: db)
    }

    static func assertSummary(_ db: Database) throws {
        for id in [patientID, otherPatientID] {
            #expect(
                try currentPatientBalance(patientID: id, in: db)
                    == patientLedger(patientID: id, in: db).balance)
        }
    }
}

struct PaymentsModelTests {
    @Test func fieldContractMatchesDomainAndSchema() throws {
        try PaymentsFixture.run { database in
            let p = PaymentsFixture.patientID
            let a = PaymentsFixture.appointmentID
            // Each row is a valid field combination from the specification.
            let valid =
                [
                    AccountEntry(kind: .charge, amount: 1, patientID: p),
                    AccountEntry(kind: .charge, amount: 1, patientID: p, appointmentID: a),
                    AccountEntry(kind: .adjustment, amount: 1, patientID: p),
                    AccountEntry(kind: .adjustment, amount: -1, patientID: p),
                ]
                + AccountEntry.Category.allCases.map { category in
                    AccountEntry(
                        kind: category.group == .incoming ? .receipt : .expense, amount: 1,
                        patientID: category == .patientFees ? p : nil, category: category)
                }
            for entry in valid {
                try entry.validate()
                try database.write { db in
                    try db.inSavepoint {
                        try AccountEntryRecord.insert {
                            AccountEntryRecord(entry, updatedAt: PaymentsFixture.now)
                        }.execute(db)
                        return .rollback
                    }
                }
                var invalid: [AccountEntry] = []
                var changed = entry
                changed.amount = 0
                invalid.append(changed)
                if entry.kind != .adjustment {
                    changed = entry
                    changed.amount = -1
                    invalid.append(changed)
                }
                changed = entry
                changed.amount = Int.min
                invalid.append(changed)
                changed = entry
                changed.patientID = entry.patientID == nil ? p : nil
                invalid.append(changed)
                if entry.kind != .charge {
                    changed = entry
                    changed.appointmentID = a
                    invalid.append(changed)
                }
                if entry.kind == .charge || entry.kind == .adjustment {
                    changed = entry
                    changed.category = .patientFees
                    invalid.append(changed)
                    changed = entry
                    changed.paymentMethod = .cash
                    invalid.append(changed)
                } else {
                    changed = entry
                    changed.category = nil
                    invalid.append(changed)
                    changed = entry
                    changed.category = entry.kind == .expense ? .otherReceipts : .rent
                    invalid.append(changed)
                }
                for invalidEntry in invalid {
                    #expect(throws: (any Error).self) { try invalidEntry.validate() }
                    try database.write { db -> Void in
                        #expect(throws: (any Error).self) {
                            try AccountEntryRecord.insert {
                                AccountEntryRecord(invalidEntry, updatedAt: PaymentsFixture.now)
                            }.execute(db)
                        }
                    }
                }
            }
            for method in AccountEntry.PaymentMethod.allCases {
                var receipt = PaymentsFixture.entry(.receipt, 1)
                receipt.paymentMethod = method
                try receipt.validate()
                var expense = PaymentsFixture.entry(.expense, 1)
                expense.paymentMethod = method
                try expense.validate()
            }
        }
    }

    @Test func normalizationMappingAndStoredEnumErrors() throws {
        try PaymentsFixture.run { _ in
            var entry = PaymentsFixture.entry(.charge, 5)
            entry.note = " \n "
            let record = AccountEntryRecord(entry, updatedAt: PaymentsFixture.now)
            #expect(record.note == nil)
            #expect(record.entryDate == FinancialDate.day(PaymentsFixture.now))
            let mapped = try record.entry()
            #expect(mapped.createdDate == entry.createdDate)
            for field in ["kind", "category", "paymentMethod"] {
                var bad = record
                switch field {
                case "kind": bad.kind = "invalid"
                case "category": bad.category = "invalid"
                default: bad.paymentMethod = "invalid"
                }
                #expect(throws: AccountEntryError.invalidStoredValue("invalid")) { try bad.entry() }
            }
            #expect(
                AccountEntry(
                    kind: .charge, amount: 1, patientID: PaymentsFixture.patientID, note: "  "
                ).note == nil)
        }
    }

    @Test func clinicDatesIgnoreDeviceCalendarAndRejectFutureDays() throws {
        var device = Calendar(identifier: .buddhist)
        device.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let midnight = try Date("2026-10-23T18:30:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = device
            $0.date.now = midnight
        } operation: {
            #expect(FinancialDate.today == midnight)
            var entry = PaymentsFixture.entry(.charge, 1, date: midnight.addingTimeInterval(86_399))
            try entry.validate()
            entry.entryDate = midnight.addingTimeInterval(86_400)
            #expect(throws: AccountEntryError.futureDate) { try entry.validate() }
            #expect(
                FinancialDate.day(midnight.addingTimeInterval(-1))
                    == midnight.addingTimeInterval(-86_400))
        }
    }

    @Test func coverageIncludesAdjustmentsAndUsesDeterministicOrder() throws {
        try PaymentsFixture.run { _ in
            let p = PaymentsFixture.patientID
            let a = PaymentsFixture.appointmentID
            let ids = [
                "00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002",
            ].map { UUID(uuidString: $0)! }
            let first = AccountEntry(
                id: ids[0], kind: .charge, amount: 5000, createdDate: PaymentsFixture.now,
                patientID: p, appointmentID: a)
            let second = AccountEntry(
                id: ids[1], kind: .charge, amount: 2000, createdDate: PaymentsFixture.now,
                patientID: p, appointmentID: a)
            let opening = PaymentsFixture.entry(.adjustment, 1000, date: PaymentsFixture.earlier)
            let receipt = PaymentsFixture.entry(.receipt, 6000)
            let adjustment = PaymentsFixture.entry(.adjustment, -500)
            let ledger = try PatientLedger(
                entries: [second, receipt, adjustment, first, opening], patientID: p)
            #expect(ledger.balance == 1500)
            #expect(ledger.moneyReceived == 6000)
            #expect(ledger.charges.map(\.covered) == [5000, 500])
            #expect(ledger.obligations.first?.covered == 1000)
            #expect(try ledger.appointment(a).amount == 7000)
            #expect(try ledger.appointment(a).remaining == 1500)
            let exact = try PatientLedger(
                entries: [first, PaymentsFixture.entry(.receipt, 5000)], patientID: p)
            #expect(exact.balance == 0)
            #expect(exact.charges.first?.remaining == 0)
            let historical = try PatientLedger(
                entries: [
                    first, PaymentsFixture.entry(.receipt, 6000, date: PaymentsFixture.earlier),
                ],
                patientID: p, through: PaymentsFixture.earlier)
            #expect(historical.balance == -6000)
            #expect(historical.unallocatedCredit == 6000)
            #expect(historical.charges.isEmpty)
            let excess = try PatientLedger(
                entries: [first, PaymentsFixture.entry(.receipt, 6000)], patientID: p)
            #expect(excess.charges.first?.covered == 5000)
            #expect(excess.unallocatedCredit == 1000)
            #expect(throws: AccountEntryError.overflow) {
                try PatientLedger(
                    entries: [
                        PaymentsFixture.entry(.charge, Int.max), PaymentsFixture.entry(.charge, 1),
                    ], patientID: p)
            }
            #expect(throws: AccountEntryError.invalidAmount) {
                try PatientLedger(
                    entries: [PaymentsFixture.entry(.adjustment, Int.min)], patientID: p)
            }
            #expect(throws: AccountEntryError.overflow) {
                try CashFlow(entries: [
                    PaymentsFixture.entry(.receipt, Int.max), PaymentsFixture.entry(.receipt, 1),
                ])
            }
        }
    }
}

struct PaymentsPersistenceTests {
    @Test func combinedSavesBackdatesEditsAndRollback() throws {
        try PaymentsFixture.run { database in
            let p = PaymentsFixture.patientID
            let charge = PaymentsFixture.entry(.charge, 5000)
            var receipt = PaymentsFixture.entry(.receipt, 5000, date: PaymentsFixture.earlier)
            try database.write { db in
                // Receipt first: temporary credit is valid within a complete batch.
                try PaymentsFixture.save(
                    [receipt, charge, PaymentsFixture.entry(.charge, 0)], in: db)
                #expect(try AccountHistoryRequest(patientID: p).fetch(db).count == 2)
                #expect(
                    try patientLedger(patientID: p, through: PaymentsFixture.earlier, in: db)
                        .balance == -5000)
                try PaymentsFixture.assertSummary(db)
                #expect(throws: AccountEntryError.negativeBalance(p)) {
                    try saveAccountEntries(AccountEntryBatch(deletes: [charge.id]), in: db)
                }
                var reduced = charge
                reduced.amount = 4000
                #expect(throws: AccountEntryError.negativeBalance(p)) {
                    try saveAccountEntries(AccountEntryBatch(updates: [reduced]), in: db)
                }
                receipt.amount = 4000
                try saveAccountEntries(AccountEntryBatch(updates: [reduced, receipt]), in: db)
                #expect(try currentPatientBalance(patientID: p, in: db) == 0)
                #expect(
                    try AccountEntryRecord.find(charge.id).fetchOne(db)?.createdAt
                        == charge.createdDate)
                #expect(throws: (any Error).self) { try PaymentsFixture.save([charge], in: db) }
                #expect(try AccountEntryRecord.find(charge.id).fetchOne(db)?.amount == 4000)
                reduced.amount = 0
                #expect(throws: AccountEntryError.invalidAmount) {
                    try saveAccountEntries(AccountEntryBatch(updates: [reduced]), in: db)
                }
                try saveAccountEntries(AccountEntryBatch(deletes: [charge.id, receipt.id]), in: db)
                #expect(try currentPatientBalance(patientID: p, in: db) == 0)
                try PaymentsFixture.assertSummary(db)
            }
        }
    }

    @Test func savepointLeavesNoChangesWhenOuterCallerCatchesFailure() throws {
        try PaymentsFixture.run { database in
            try database.write { db in
                let failed = PaymentsFixture.entry(.receipt, 50)
                #expect(throws: AccountEntryError.negativeBalance(PaymentsFixture.patientID)) {
                    try PaymentsFixture.save([failed], in: db)
                }
                #expect(try AccountEntryRecord.find(failed.id).fetchOne(db) == nil)
                #expect(
                    try PatientBalanceRecord.find(PaymentsFixture.patientID).fetchOne(db) == nil)
                try PaymentsFixture.save([PaymentsFixture.entry(.charge, 10)], in: db)
            }
            #expect(
                try database.read {
                    try AccountHistoryRequest(patientID: PaymentsFixture.patientID).fetch($0).count
                } == 1)
        }
    }

    @Test func summaryTracksKindAndPatientChangesAndRebuild() throws {
        try PaymentsFixture.run { database in
            var charge = PaymentsFixture.entry(.charge, 100)
            var receipt = PaymentsFixture.entry(.receipt, 40)
            try database.write { db in
                try PaymentsFixture.save(
                    [charge, receipt, PaymentsFixture.entry(.expense, 12)], in: db)
                try PaymentsFixture.assertSummary(db)
                charge.patientID = PaymentsFixture.otherPatientID
                #expect(throws: AccountEntryError.negativeBalance(PaymentsFixture.patientID)) {
                    try saveAccountEntries(AccountEntryBatch(updates: [charge]), in: db)
                }
                receipt.patientID = PaymentsFixture.otherPatientID
                try saveAccountEntries(AccountEntryBatch(updates: [charge, receipt]), in: db)
                try PaymentsFixture.assertSummary(db)
                charge.kind = .adjustment
                charge.amount = 70
                receipt.patientID = nil
                receipt.category = .otherReceipts
                try saveAccountEntries(AccountEntryBatch(updates: [charge, receipt]), in: db)
                try PaymentsFixture.assertSummary(db)
                #expect(
                    try currentPatientBalance(patientID: PaymentsFixture.otherPatientID, in: db)
                        == 70)
                try db.execute(sql: "UPDATE patientBalances SET balance = 999")
                try rebuildPatientBalances(in: db)
                try PaymentsFixture.assertSummary(db)
                try rebuildPatientBalances(in: db)
                try PaymentsFixture.assertSummary(db)
            }
        }
    }

    @Test func knownBalanceUsesStoredDatedHistoryBeforePairedReceipt() throws {
        try PaymentsFixture.run { database in
            try database.write { db in
                let old = PaymentsFixture.entry(.charge, 5000, date: PaymentsFixture.earlier)
                try PaymentsFixture.save([old, PaymentsFixture.entry(.charge, 1000)], in: db)
                let receipt = PaymentsFixture.entry(.receipt, 7000, date: PaymentsFixture.earlier)
                try correctPatientBalance(
                    patientID: PaymentsFixture.patientID, to: 7000,
                    through: PaymentsFixture.earlier, receipt: receipt, in: db)
                let history = try AccountHistoryRequest(patientID: PaymentsFixture.patientID).fetch(
                    db)
                #expect(history.first { $0.kind == .adjustment }?.amount == 2000)
                #expect(
                    try currentPatientBalance(patientID: PaymentsFixture.patientID, in: db) == 1000)
                let cash = try CashFlow(entries: history)
                #expect(cash.received == 7000)
                #expect(history.filter { $0.kind == .charge }.map(\.amount).reduce(0, +) == 6000)
                try correctPatientBalance(
                    patientID: PaymentsFixture.patientID, to: 1000, through: PaymentsFixture.now,
                    in: db)
                #expect(
                    try AccountHistoryRequest(patientID: PaymentsFixture.patientID).fetch(db).count
                        == history.count)
                #expect(throws: AccountEntryError.negativeTargetBalance) {
                    try correctPatientBalance(
                        patientID: PaymentsFixture.patientID, to: -1, through: PaymentsFixture.now,
                        in: db)
                }
                try PaymentsFixture.assertSummary(db)
            }
        }
    }

    @Test func referenceRulesHoldForRawWritesAndSettledHistory() throws {
        try PaymentsFixture.run { database in
            try database.write { db in
                var charge = PaymentsFixture.entry(.charge, 50)
                charge.appointmentID = PaymentsFixture.appointmentID
                var mismatch = charge
                mismatch.patientID = PaymentsFixture.otherPatientID
                #expect(throws: AccountEntryError.appointmentPatientMismatch) {
                    try PaymentsFixture.save([mismatch], in: db)
                }
                #expect(throws: (any Error).self) {
                    try AccountEntryRecord.insert {
                        AccountEntryRecord(mismatch, updatedAt: PaymentsFixture.now)
                    }.execute(db)
                }
                var second = PaymentsFixture.entry(.charge, 50)
                second.appointmentID = charge.appointmentID
                try PaymentsFixture.save(
                    [charge, second, PaymentsFixture.entry(.receipt, 100)], in: db)
                #expect(
                    try AppointmentChargesRequest(appointmentID: PaymentsFixture.appointmentID)
                        .fetch(db).count == 2)
                #expect(
                    try AppointmentCoverageRequest(appointmentID: PaymentsFixture.appointmentID)
                        .fetch(db).covered == 100)
                #expect(throws: (any Error).self) {
                    try AppointmentRecord.find(PaymentsFixture.appointmentID).delete().execute(db)
                }
                #expect(throws: (any Error).self) {
                    try AppointmentRecord.find(PaymentsFixture.appointmentID).update {
                        $0.patientID = #bind(PaymentsFixture.otherPatientID)
                    }.execute(db)
                }
                #expect(throws: AccountEntryError.appointmentHasCharges) {
                    try validateAppointmentPatientChange(
                        id: PaymentsFixture.appointmentID,
                        patientID: PaymentsFixture.otherPatientID, in: db)
                }
                #expect(throws: (any Error).self) {
                    try PatientRecord.find(PaymentsFixture.patientID).delete().execute(db)
                }
                try AppointmentRecord.find(PaymentsFixture.appointmentID).update {
                    $0.status = "cancelled"
                }.execute(db)
                #expect(
                    try AppointmentChargesRequest(appointmentID: PaymentsFixture.appointmentID)
                        .fetch(db).count == 2)
                // The update guard also applies when an existing charge gains a wrong link.
                #expect(throws: (any Error).self) {
                    try AccountEntryRecord.find(charge.id).update {
                        $0.patientID = #bind(PaymentsFixture.otherPatientID)
                    }.execute(db)
                }
                try PaymentsFixture.assertSummary(db)
            }
        }
    }

    @Test func explicitMissingReferenceErrorsAndOverflowRollback() throws {
        try PaymentsFixture.run { database in
            try database.write { db in
                let missing = UUID()
                #expect(throws: AccountEntryError.missingEntry(missing)) {
                    try saveAccountEntries(AccountEntryBatch(deletes: [missing]), in: db)
                }
                var charge = PaymentsFixture.entry(.charge, 10)
                charge.patientID = missing
                #expect(throws: AccountEntryError.missingPatient(missing)) {
                    try PaymentsFixture.save([charge], in: db)
                }
                charge.patientID = PaymentsFixture.patientID
                charge.appointmentID = missing
                #expect(throws: AccountEntryError.missingAppointment(missing)) {
                    try PaymentsFixture.save([charge], in: db)
                }
                try PaymentsFixture.save([PaymentsFixture.entry(.charge, Int.max)], in: db)
                #expect(throws: (any Error).self) {
                    try PaymentsFixture.save([PaymentsFixture.entry(.charge, 1)], in: db)
                }
                #expect(
                    try currentPatientBalance(patientID: PaymentsFixture.patientID, in: db)
                        == Int.max)
                #expect(
                    try AccountHistoryRequest(patientID: PaymentsFixture.patientID).fetch(db).count
                        == 1)
            }
        }
    }
}

struct PaymentsQueryTests {
    @Test func periodReportsUseClinicDatesAndKeepUnknownMethods() throws {
        try PaymentsFixture.run { database in
            try database.write { db in
                let start = try Date("2026-10-19T18:30:00Z", strategy: .iso8601)
                let end = FinancialDate.nextDay(start)
                let entries = [
                    AccountEntry(
                        kind: .receipt, amount: 100, entryDate: start,
                        category: .externalConsultations, note: "Referral"),
                    AccountEntry(
                        kind: .receipt, amount: 50, entryDate: start,
                        category: .externalConsultations, note: "Referral", paymentMethod: .upi),
                    AccountEntry(
                        kind: .expense, amount: 20, entryDate: start, category: .rent,
                        note: "Monthly", paymentMethod: .cash),
                    AccountEntry(
                        kind: .expense, amount: 200, entryDate: start, category: .equipmentPurchases
                    ),
                    AccountEntry(
                        kind: .receipt, amount: 999, entryDate: end, category: .otherReceipts),
                    AccountEntry(
                        kind: .receipt, amount: 888, entryDate: start.addingTimeInterval(-1),
                        category: .otherReceipts),
                    PaymentsFixture.entry(.adjustment, 500, date: start),
                    PaymentsFixture.entry(.charge, 500, date: start),
                ]
                try PaymentsFixture.save(entries, in: db)
                let report = try CashFlowRequest(start: start, end: end).fetch(db)
                #expect(report.received == 150)
                #expect(report.paid == 220)
                #expect(report.net == -70)
                let unknown = try report.amounts(paymentMethod: nil)
                #expect(unknown.received == 100)
                #expect(unknown.paid == 200)
                #expect(unknown.net == -100)
                #expect(try report.total(for: AccountEntry.Category.externalConsultations) == 150)
                #expect(try report.total(for: .capital) == 200)
                #expect(try report.total(for: .operating) == 20)
                #expect(
                    report.totals.filter { $0.key.paymentMethod == nil }.values.sorted() == [
                        100, 200,
                    ])
                #expect(
                    try PreviousAccountNotesRequest(category: .externalConsultations).fetch(db) == [
                        "Referral"
                    ])
                #expect(try PreviousAccountNotesRequest(category: .rent).fetch(db) == ["Monthly"])
            }
        }
    }

    @Test func reportsDoNotSilentlyOmitInvalidStoredKinds() throws {
        try PaymentsFixture.run { database in
            try database.write { db in
                try PaymentsFixture.save([PaymentsFixture.entry(.charge, 100)], in: db)
                // Model damaged storage without weakening the production schema.
                try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
                try db.execute(sql: "UPDATE accountEntries SET kind = 'unexpected'")
                #expect(throws: AccountEntryError.invalidStoredValue("unexpected")) {
                    try CashFlowRequest(
                        start: PaymentsFixture.now,
                        end: FinancialDate.nextDay(PaymentsFixture.now)
                    ).fetch(db)
                }
                #expect(throws: AccountEntryError.invalidStoredValue("unexpected")) {
                    try AccountHistoryRequest(patientID: PaymentsFixture.patientID).fetch(db)
                }
            }
        }
    }

    @Test func summaryJoinsDoNotMultiplyAcrossAppointments() throws {
        try PaymentsFixture.run { database in
            try database.write { db in
                let second = try AppointmentRecord.persisted(
                    id: UUID(), patientID: PaymentsFixture.patientID,
                    start: PaymentsFixture.now, durationMinutes: 30, status: .scheduled,
                    createdAt: PaymentsFixture.now, updatedAt: PaymentsFixture.now)
                try AppointmentRecord.insert { second }.execute(db)
                #expect(
                    try currentPatientBalance(patientID: PaymentsFixture.patientID, in: db) == 0)
                try PaymentsFixture.save([PaymentsFixture.entry(.charge, 100)], in: db)
                let rows = try PatientAccountsRequest(now: PaymentsFixture.now, owingOnly: true)
                    .fetch(db)
                #expect(rows.count == 1)
                #expect(rows.first?.currentBalance == 100)
                #expect(rows.first?.nextAppointmentDate == PaymentsFixture.now)
                #expect(try OutstandingBalanceRequest().fetch(db) == 100)
                let all = try PatientAccountsRequest(now: PaymentsFixture.now).fetch(db)
                #expect(all.first { $0.id == PaymentsFixture.otherPatientID }?.currentBalance == 0)
            }
        }
    }

    @Test func observedDomainQueriesUpdateAfterLedgerWrites() async throws {
        let database = try PaymentsFixture.database()
        try await withDependencies {
            $0.date.now = PaymentsFixture.now
            $0.defaultDatabase = database
        } operation: {
            @Fetch(PatientAccountsRequest(now: PaymentsFixture.now, owingOnly: true)) var patients:
                [PatientDetails] = []
            @Fetch(CurrentPatientBalanceRequest(patientID: PaymentsFixture.patientID)) var balance =
                0
            @Fetch(OutstandingBalanceRequest()) var outstanding = 0
            @Fetch(AccountHistoryRequest(patientID: PaymentsFixture.patientID)) var history:
                [AccountEntry] = []
            try await $patients.load()
            try await $balance.load()
            try await $outstanding.load()
            try await $history.load()
            #expect(patients.isEmpty)
            let charge = PaymentsFixture.entry(.charge, 100)
            try await database.createAccountEntry(charge)
            for _ in 0..<200 {
                if balance == 100 && outstanding == 100 && patients.first?.currentBalance == 100
                    && history.count == 1
                {
                    break
                }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(balance == 100)
            #expect(outstanding == 100)
            #expect(patients.first?.currentBalance == 100)
            #expect(history.count == 1)
            try await database.createAccountEntry(PaymentsFixture.entry(.receipt, 100))
            for _ in 0..<200 {
                if balance == 0 && outstanding == 0 && patients.isEmpty && history.count == 2 {
                    break
                }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(balance == 0)
            #expect(outstanding == 0)
            #expect(patients.isEmpty)
            #expect(history.count == 2)
        }
    }

    @Test func freshSchemaContainsIndexesTriggersAndForeignKeys() throws {
        try PaymentsFixture.run { database in
            try database.read { db in
                let indexes = try String.fetchAll(
                    db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'")
                #expect(
                    Set(indexes).isSuperset(of: [
                        "idx_accountEntries_patient", "idx_accountEntries_appointment",
                        "idx_accountEntries_date", "idx_patientBalances_positive",
                    ]))
                let triggers = try String.fetchAll(
                    db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger'")
                #expect(
                    Set(triggers).isSuperset(of: [
                        "accountEntry_summary_insert", "accountEntry_summary_update",
                        "accountEntry_summary_delete", "accountEntry_patient_insert",
                        "accountEntry_patient_update", "appointment_charged_patient",
                    ]))
                #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            }
        }
    }
}

struct PaymentsBoundaryTests {
    @Test func editsPreserveStoredCreationTimeAndNormalizeChangedDate() throws {
        try PaymentsFixture.run { database in
            let charge = PaymentsFixture.entry(.charge, 100)
            try database.write { db in
                try PaymentsFixture.save([charge], in: db)
                let editTime = PaymentsFixture.now.addingTimeInterval(60)
                try withDependencies {
                    $0.date.now = editTime
                } operation: {
                    let changed = AccountEntry(
                        id: charge.id, kind: .charge, amount: 200,
                        entryDate: PaymentsFixture.earlier, createdDate: editTime,
                        patientID: PaymentsFixture.patientID, note: " \n ")
                    try saveAccountEntries(AccountEntryBatch(updates: [changed]), in: db)
                }
                let stored = try #require(try AccountEntryRecord.find(charge.id).fetchOne(db))
                #expect(stored.createdAt == charge.createdDate)
                #expect(stored.updatedAt == editTime)
                #expect(stored.entryDate == FinancialDate.day(PaymentsFixture.earlier))
                #expect(stored.note == nil)
                #expect(
                    try patientLedger(
                        patientID: PaymentsFixture.patientID, through: PaymentsFixture.earlier,
                        in: db
                    ).balance == 200)
                #expect(throws: AccountEntryError.duplicateMutation(charge.id)) {
                    try saveAccountEntries(
                        AccountEntryBatch(updates: [charge], deletes: [charge.id]), in: db)
                }
                try PaymentsFixture.assertSummary(db)
            }
        }
    }

    @Test func futureDatesFailForEveryKindAndForEdits() throws {
        try PaymentsFixture.run { database in
            try database.write { db in
                for kind in AccountEntry.Kind.allCases {
                    let entry = PaymentsFixture.entry(
                        kind, 100, date: FinancialDate.nextDay(PaymentsFixture.now))
                    #expect(throws: AccountEntryError.futureDate) {
                        try PaymentsFixture.save([entry], in: db)
                    }
                }
                var charge = PaymentsFixture.entry(.charge, 100)
                try PaymentsFixture.save([charge], in: db)
                charge.entryDate = FinancialDate.nextDay(PaymentsFixture.now)
                #expect(throws: AccountEntryError.futureDate) {
                    try saveAccountEntries(AccountEntryBatch(updates: [charge]), in: db)
                }
                #expect(
                    try AccountHistoryRequest(patientID: PaymentsFixture.patientID).fetch(db).count
                        == 1)
            }
        }
    }

    @Test func chargesAcceptAllStoredAppointmentStatuses() throws {
        try PaymentsFixture.run { database in
            try database.write { db in
                for status in [Appointment.Status.scheduled, .completed, .cancelled] {
                    let appointment = try AppointmentRecord.persisted(
                        id: UUID(), patientID: PaymentsFixture.patientID,
                        start: PaymentsFixture.now, durationMinutes: 30, status: status,
                        createdAt: PaymentsFixture.now, updatedAt: PaymentsFixture.now)
                    try AppointmentRecord.insert { appointment }.execute(db)
                    var charge = PaymentsFixture.entry(.charge, 100)
                    charge.appointmentID = appointment.id
                    try PaymentsFixture.save([charge], in: db)
                }
                #expect(
                    try currentPatientBalance(patientID: PaymentsFixture.patientID, in: db) == 300)
            }
        }
    }

    @Test func pureCoverageChangesWithFinancialDateAndCreationOrder() throws {
        try PaymentsFixture.run { _ in
            var first = PaymentsFixture.entry(.charge, 50)
            let second = AccountEntry(
                kind: .charge, amount: 50, entryDate: PaymentsFixture.now,
                createdDate: PaymentsFixture.earlier, patientID: PaymentsFixture.patientID)
            let receipt = PaymentsFixture.entry(.receipt, 60)
            let ledger = try PatientLedger(
                entries: [first, second, receipt], patientID: PaymentsFixture.patientID)
            #expect(ledger.charges.map(\.entryID) == [second.id, first.id])
            #expect(ledger.charges.map(\.covered) == [50, 10])
            first.entryDate = FinancialDate.day(PaymentsFixture.earlier)
            let backdated = try PatientLedger(
                entries: [first, second, receipt], patientID: PaymentsFixture.patientID)
            #expect(backdated.charges.map(\.entryID) == [first.id, second.id])
            #expect(backdated.charges.map(\.covered) == [50, 10])
        }
    }

    @Test func schemaRejectsUnknownEnumsAndSummaryOverflowOnUpdate() throws {
        try PaymentsFixture.run { database in
            try database.write { db in
                let charge = PaymentsFixture.entry(.charge, Int.max)
                try PaymentsFixture.save([charge], in: db)
                for field in ["kind", "category", "paymentMethod"] {
                    #expect(throws: (any Error).self) {
                        try db.execute(sql: "UPDATE accountEntries SET \(field) = 'unexpected'")
                    }
                }
                let receipt = PaymentsFixture.entry(.receipt, 1)
                try PaymentsFixture.save([receipt], in: db)
                var negative = receipt
                negative.kind = .adjustment
                negative.amount = -1
                negative.category = nil
                try saveAccountEntries(AccountEntryBatch(updates: [negative]), in: db)
                var positive = negative
                positive.amount = 1
                #expect(throws: (any Error).self) {
                    try saveAccountEntries(AccountEntryBatch(updates: [positive]), in: db)
                }
                #expect(
                    try currentPatientBalance(patientID: PaymentsFixture.patientID, in: db) == Int
                        .max - 1)
                try PaymentsFixture.assertSummary(db)
            }
        }
    }

    @Test func summaryAloneDoesNotPreventPatientDeletionAndRebuildRollsBack() throws {
        try PaymentsFixture.run { database in
            try database.write { db in
                let charge = PaymentsFixture.entry(.charge, 100)
                try PaymentsFixture.save([charge], in: db)
                try saveAccountEntries(AccountEntryBatch(deletes: [charge.id]), in: db)
                #expect(
                    try PatientBalanceRecord.find(PaymentsFixture.patientID).fetchOne(db)?.balance
                        == 0)
                try PatientRecord.find(PaymentsFixture.patientID).delete().execute(db)
                #expect(
                    try PatientBalanceRecord.find(PaymentsFixture.patientID).fetchOne(db) == nil)
                // Simulate a partial import whose grouped SUM cannot fit in an integer.
                let p = PaymentsFixture.otherPatientID
                try db.execute(sql: "DROP TRIGGER accountEntry_summary_insert")
                let huge = AccountEntry(kind: .charge, amount: Int.max, patientID: p)
                let one = AccountEntry(kind: .charge, amount: 1, patientID: p)
                for entry in [huge, one] {
                    try AccountEntryRecord.insert {
                        AccountEntryRecord(entry, updatedAt: PaymentsFixture.now)
                    }.execute(db)
                }
                try #sql(
                    """
                    INSERT INTO patientBalances VALUES
                    (\(bind: p), 7, \(bind: PaymentsFixture.now), \(bind: PaymentsFixture.now))
                    """
                ).execute(db)
                #expect(throws: (any Error).self) { try rebuildPatientBalances(in: db) }
                #expect(try currentPatientBalance(patientID: p, in: db) == 7)
            }
        }
    }

    @Test func writerWrappersKeepOneTransactionForCorrections() async throws {
        let database = try PaymentsFixture.database()
        try await withDependencies {
            $0.date.now = PaymentsFixture.now
        } operation: {
            var charge = PaymentsFixture.entry(.charge, 100)
            try await database.createAccountEntry(charge)
            charge.amount = 150
            try await database.editAccountEntry(charge)
            try await database.correctPatientBalance(
                patientID: PaymentsFixture.patientID, to: 200,
                through: PaymentsFixture.now, receipt: PaymentsFixture.entry(.receipt, 200))
            try await database.rebuildPatientBalances()
            try await database.read { db in
                #expect(
                    try currentPatientBalance(patientID: PaymentsFixture.patientID, in: db) == 0)
                try PaymentsFixture.assertSummary(db)
            }
            await #expect(throws: AccountEntryError.negativeBalance(PaymentsFixture.patientID)) {
                try await database.deleteAccountEntry(id: charge.id)
            }
        }
    }
}
