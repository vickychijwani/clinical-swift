import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

struct AppointmentCompletionPersistenceTests {
    private nonisolated static let p = PaymentsFixture.patientID
    private nonisolated static let a = PaymentsFixture.appointmentID

    @Test(arguments: [nil, AccountEntry.PaymentMethod.upi, .cash, .card, .other])
    func newChargeAndReceiptUseSaveClockAndOptionalMethod(_ method: AccountEntry.PaymentMethod?)
        async throws
    {
        let database = try PaymentsFixture.database()
        let timestamp = try Date("2026-10-25T18:45:00Z", strategy: .iso8601)
        try await withDependencies {
            $0.date.now = timestamp
            $0.calendar = Calendar(identifier: .islamic)
            $0.locale = Locale(identifier: "en_US")
        } operation: {
            try await database.completeAppointment(
                id: Self.a, patientID: Self.p, amount: 1000, paymentMethod: method)
        }
        try await database.read { db in
            let records = try AccountEntryRecord.all.fetchAll(db)
            #expect(records.count == 2)
            let charge = try #require(records.first { $0.kind == "charge" })
            let receipt = try #require(records.first { $0.kind == "receipt" })
            #expect(charge.appointmentID == Self.a)
            #expect(receipt.appointmentID == nil)
            #expect(receipt.category == "patientFees")
            #expect(receipt.paymentMethod == method?.rawValue)
            for record in records {
                #expect(record.amount == 1000)
                #expect(record.patientID == Self.p)
                #expect(record.createdAt == timestamp)
                #expect(record.updatedAt == timestamp)
                #expect(record.entryDate == FinancialDate.day(timestamp))
                #expect(record.note == nil)
            }
            let appointment = try #require(try AppointmentRecord.find(Self.a).fetchOne(db))
            #expect(appointment.status == "completed")
            #expect(appointment.updatedAt == timestamp)
            #expect(try currentPatientBalance(patientID: Self.p, in: db) == 0)
            try PaymentsFixture.assertSummary(db)
        }
    }

    @Test(arguments: [0, 1000, 1500, 2000])
    func existingChargeIsReplacedOrDeletedWithoutChangingHistory(_ amount: Int) async throws {
        let database = try PaymentsFixture.database()
        let oldCharge = linkedCharge(1500)
        try await withDependencies {
            $0.date.now = PaymentsFixture.now
        } operation: {
            try await database.createAccountEntry(oldCharge)
            try await database.completeAppointment(
                id: Self.a, patientID: Self.p, amount: amount, paymentMethod: nil)
        }
        try await database.read { db in
            let records = try AccountEntryRecord.all.fetchAll(db)
            if amount == 0 {
                #expect(records.isEmpty)
            } else {
                #expect(records.count == 2)
                let edited = try #require(try AccountEntryRecord.find(oldCharge.id).fetchOne(db))
                #expect(edited.amount == amount)
                #expect(edited.createdAt == oldCharge.createdDate)
                #expect(edited.entryDate == oldCharge.entryDate)
                #expect(edited.note == oldCharge.note)
                #expect(edited.patientID == oldCharge.patientID)
                #expect(edited.appointmentID == oldCharge.appointmentID)
                #expect(edited.updatedAt == PaymentsFixture.now)
            }
            #expect(try currentPatientBalance(patientID: Self.p, in: db) == 0)
            try PaymentsFixture.assertSummary(db)
        }
    }

    @Test func zeroWithoutChargeCreatesNoEntries() async throws {
        let database = try PaymentsFixture.database()
        try await withDependencies {
            $0.date.now = PaymentsFixture.now
        } operation: {
            try await database.completeAppointment(
                id: Self.a, patientID: Self.p, amount: 0, paymentMethod: .card)
        }
        try await database.read { db in
            let entries = try AccountEntryRecord.all.fetchAll(db)
            let appointment = try AppointmentRecord.find(Self.a).fetchOne(db)
            #expect(entries.isEmpty)
            #expect(appointment?.status == "completed")
        }
    }

    @Test(arguments: [0, 1000])
    func earlierReceiptsCanRejectTheWholeCompletion(_ amount: Int) async throws {
        let database = try PaymentsFixture.database()
        try await withDependencies {
            $0.date.now = PaymentsFixture.now
        } operation: {
            try await database.saveAccountEntries(
                .init(inserts: [linkedCharge(1500), PaymentsFixture.entry(.receipt, 500)]))
            let before = try await snapshot(database)
            await #expect(throws: AccountEntryError.negativeBalance(Self.p)) {
                try await database.completeAppointment(
                    id: Self.a, patientID: Self.p, amount: amount, paymentMethod: .cash)
            }
            #expect(try await snapshot(database) == before)
        }
    }

    @Test(arguments: [0, 1000])
    func olderDebtUsesPatientCoverageAndPreservesReceipts(_ amount: Int) async throws {
        let database = try PaymentsFixture.database()
        let oldReceipt = PaymentsFixture.entry(.receipt, 200)
        try await withDependencies {
            $0.date.now = PaymentsFixture.now
        } operation: {
            try await database.saveAccountEntries(
                .init(inserts: [
                    PaymentsFixture.entry(
                        .charge, 2000, date: PaymentsFixture.earlier.addingTimeInterval(-86400)),
                    oldReceipt, linkedCharge(1500),
                ]))
            try await database.completeAppointment(
                id: Self.a, patientID: Self.p, amount: amount, paymentMethod: nil)
        }
        try await database.read { db in
            #expect(try currentPatientBalance(patientID: Self.p, in: db) == 1800)
            #expect(try AccountEntryRecord.find(oldReceipt.id).fetchOne(db)?.entry() == oldReceipt)
            let ledger = try patientLedger(patientID: Self.p, in: db)
            #expect(try ledger.appointment(Self.a).covered == 0)
            try PaymentsFixture.assertSummary(db)
        }
    }

    @Test func multipleChargesAndStaleOwnershipRejectBeforeWrites() async throws {
        let database = try PaymentsFixture.database()
        try await withDependencies {
            $0.date.now = PaymentsFixture.now
        } operation: {
            try await database.saveAccountEntries(
                .init(inserts: [linkedCharge(100), linkedCharge(200)]))
            let before = try await snapshot(database)
            await #expect(throws: AppointmentCompletionError.multipleCharges) {
                try await database.completeAppointment(
                    id: Self.a, patientID: Self.p, amount: 1000, paymentMethod: nil)
            }
            await #expect(throws: AppointmentCompletionError.patientChanged) {
                try await database.completeAppointment(
                    id: Self.a, patientID: PaymentsFixture.otherPatientID, amount: 1000,
                    paymentMethod: nil)
            }
            await #expect(throws: AppointmentCompletionError.invalidAmount) {
                try await database.completeAppointment(
                    id: Self.a, patientID: Self.p, amount: -1, paymentMethod: nil)
            }
            #expect(try await snapshot(database) == before)
        }
    }

    @Test(arguments: [Appointment.Status.completed, .cancelled])
    func terminalAppointmentCannotChangeMoney(_ status: Appointment.Status) async throws {
        let database = try PaymentsFixture.database()
        try await withDependencies {
            $0.date.now = PaymentsFixture.now
        } operation: {
            try await database.saveAccountEntries(
                .init(inserts: [linkedCharge(1500), PaymentsFixture.entry(.receipt, 500)]))
            _ = try await database.updateAppointmentStatus(
                id: Self.a, to: status, at: PaymentsFixture.now)
            let before = try await snapshot(database)
            await #expect(throws: AppointmentCompletionError.notScheduled) {
                try await database.completeAppointment(
                    id: Self.a, patientID: Self.p, amount: 1000, paymentMethod: nil)
            }
            await #expect(throws: AppointmentCompletionError.notScheduled) {
                try await database.completeAppointment(
                    id: Self.a, patientID: Self.p, amount: 0, paymentMethod: nil)
            }
            #expect(try await snapshot(database) == before)
            await #expect(throws: AppointmentCompletionError.unavailable) {
                try await database.completeAppointment(
                    id: UUID(), patientID: Self.p, amount: 1000, paymentMethod: nil)
            }
        }
    }

    @Test func competingCompletionsCommitOnlyOneReceipt() async throws {
        let database = try PaymentsFixture.database()
        let results = await withDependencies {
            $0.date.now = PaymentsFixture.now
        } operation: {
            let first = Task {
                try await database.completeAppointment(
                    id: Self.a, patientID: Self.p, amount: 1000, paymentMethod: nil)
            }
            let second = Task {
                try await database.completeAppointment(
                    id: Self.a, patientID: Self.p, amount: 2000, paymentMethod: .upi)
            }
            return await [first.result, second.result]
        }
        #expect(results.filter { if case .success = $0 { true } else { false } }.count == 1)
        try await database.read { db in
            #expect(try AccountEntryRecord.all.fetchAll(db).count == 2)
            try PaymentsFixture.assertSummary(db)
        }
    }

    @Test(arguments: [
        "chargeInsert", "receiptInsert", "chargeUpdate", "chargeDelete", "appointmentUpdate",
    ])
    func storageFailureRollsBackAllWritesAndAllowsRetry(_ failure: String) async throws {
        let database = try PaymentsFixture.database()
        try await withDependencies {
            $0.date.now = PaymentsFixture.now
        } operation: {
            if failure == "chargeUpdate" || failure == "chargeDelete" {
                try await database.createAccountEntry(linkedCharge(1500))
            }
            let statements = [
                "chargeInsert": "BEFORE INSERT ON accountEntries WHEN NEW.kind = 'charge'",
                "receiptInsert": "BEFORE INSERT ON accountEntries WHEN NEW.kind = 'receipt'",
                "chargeUpdate": "BEFORE UPDATE ON accountEntries WHEN OLD.kind = 'charge'",
                "chargeDelete": "BEFORE DELETE ON accountEntries WHEN OLD.kind = 'charge'",
                "appointmentUpdate": "BEFORE UPDATE ON appointments",
            ]
            let statement = try #require(statements[failure])
            try await database.write { db in
                try db.execute(
                    sql:
                        "CREATE TRIGGER failCompletion \(statement) BEGIN SELECT RAISE(ABORT, 'injected failure'); END"
                )
            }
            let before = try await snapshot(database)
            await #expect(throws: (any Error).self) {
                try await database.completeAppointment(
                    id: Self.a, patientID: Self.p, amount: failure == "chargeDelete" ? 0 : 1000,
                    paymentMethod: .upi)
            }
            #expect(try await snapshot(database) == before)
            try await database.write { db in try db.execute(sql: "DROP TRIGGER failCompletion") }
            try await database.completeAppointment(
                id: Self.a, patientID: Self.p, amount: 1000, paymentMethod: .upi)
        }
    }

    @Test func integerLimitIsSupportedAndLedgerOverflowRollsBack() async throws {
        let database = try PaymentsFixture.database()
        try await withDependencies {
            $0.date.now = PaymentsFixture.now
        } operation: {
            try await database.completeAppointment(
                id: Self.a, patientID: Self.p, amount: Int.max, paymentMethod: nil)
        }
        let amounts = try await database.read { db in
            try AccountEntryRecord.all.fetchAll(db).map(\.amount)
        }
        #expect(amounts == [Int.max, Int.max])

        let overflowing = try PaymentsFixture.database()
        try await withDependencies {
            $0.date.now = PaymentsFixture.now
        } operation: {
            try await overflowing.saveAccountEntries(
                .init(inserts: [
                    PaymentsFixture.entry(.charge, Int.max - 1500), linkedCharge(1500),
                ]))
            let before = try await snapshot(overflowing)
            await #expect(throws: (any Error).self) {
                try await overflowing.completeAppointment(
                    id: Self.a, patientID: Self.p, amount: 2000, paymentMethod: nil)
            }
            #expect(try await snapshot(overflowing) == before)
        }
    }

    private nonisolated func linkedCharge(_ amount: Int) -> AccountEntry {
        AccountEntry(
            details: .charge(patientID: Self.p, appointmentID: Self.a), amount: amount,
            entryDate: PaymentsFixture.earlier, createdDate: PaymentsFixture.earlier,
            note: "Keep this note")
    }

    private func snapshot(_ database: DatabaseQueue) async throws -> [[String]] {
        try await database.read { db in
            try ["appointments", "accountEntries", "patientBalances"].map {
                try Row.fetchAll(db, sql: "SELECT * FROM \($0) ORDER BY id").map { $0.description }
            }
        }
    }
}
