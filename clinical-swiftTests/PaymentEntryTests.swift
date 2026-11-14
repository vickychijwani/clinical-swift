import ClinicalModels
import ClinicalPersistence
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct PaymentEntryTests {
    @Test func patientMustBeSelectedAndEditingNameClearsSelection() throws {
        try withDependencies {
            $0.defaultDatabase = try testDatabase()
        } operation: {
            let model = PaymentEntryModel()
            #expect(model.kind == .patient)
            #expect(!model.canAdd)
            model.amountText = "500"
            model.setNote("Anjali")
            #expect(!model.canAdd)
            model.selectPatient(Patient(name: "Anjali Desai"))
            #expect(model.canAdd)
            model.setNote(model.note)
            #expect(model.canAdd)
            model.setNote("Anjali D")
            #expect(!model.canAdd)
        }
    }

    @Test func typeChangeClearsNoteAndCustomLabelsNeedAPositiveAmount() throws {
        try withDependencies {
            $0.defaultDatabase = try testDatabase()
        } operation: {
            let model = PaymentEntryModel()
            model.selectPatient(Patient(name: "Anjali Desai"))
            model.amountText = "500"
            model.selectKind(.expense)
            #expect(model.patient == nil)
            #expect(model.note.isEmpty)
            #expect(!model.canAdd)
            model.setNote("   ")
            #expect(!model.canAdd)
            model.setNote("New lab")
            #expect(model.canAdd)
            for value in ["", "0", "-500", "abc"] {
                model.amountText = value
                #expect(!model.canAdd)
            }
        }
    }

    @Test func suggestionsStayWithinKindAndReuseExistingSpelling() async throws {
        let date = try Date("2026-11-04T10:00:00Z", strategy: .iso8601)
        let earlier = try Date("2026-11-03T10:00:00Z", strategy: .iso8601)
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = try testDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var database
            let entries = [
                AccountEntry(
                    details: .expense(category: nil, paymentMethod: nil),
                    amount: 100, note: "Dental Lab"),
                AccountEntry(
                    details: .expense(category: .materials, paymentMethod: nil),
                    amount: 100, createdDate: earlier, note: "dental lab"),
                AccountEntry(
                    details: .expense(category: .materials, paymentMethod: nil),
                    amount: 100, createdDate: earlier, note: "Gloves"),
                AccountEntry(
                    details: .receipt(source: .externalConsultations, paymentMethod: nil),
                    amount: 100, note: "Visiting clinic"),
                AccountEntry(
                    details: .receipt(source: .externalConsultations, paymentMethod: nil),
                    amount: 100, createdDate: earlier, note: "VISITING CLINIC"),
                AccountEntry(
                    details: .receipt(source: .referralCommissions, paymentMethod: nil),
                    amount: 100, note: "Referral clinic"),
            ]
            try await database.write { db in
                try saveAccountEntries(AccountEntryBatch(inserts: entries), in: db)
            }
            let model = PaymentEntryModel()
            model.selectKind(.expense)
            #expect(model.labels == ["Dental Lab", "Gloves"])
            model.setNote("den")
            #expect(model.matchingLabels == ["Dental Lab"])
            model.setNote("  DENTAL LAB  ")
            model.finishNote()
            #expect(model.note == "Dental Lab")
            model.setNote("New lab")
            model.finishNote()
            #expect(model.note == "New lab")
            model.selectKind(.consult)
            #expect(model.labels == ["Visiting clinic"])
            model.setNote(" VISITING CLINIC ")
            model.finishNote()
            #expect(model.note == "Visiting clinic")
            model.selectKind(.referral)
            #expect(model.labels == ["Referral clinic"])
            let count = try await database.read { try AccountEntryRecord.count().fetchOne($0) }
            #expect(count == entries.count)
        }
    }

    @Test(arguments: [PaymentEntryModel.Kind.expense, .consult])
    func savedLabelAppearsWhileTheKindStaysSelected(_ kind: PaymentEntryModel.Kind) async throws {
        let date = try Date("2026-11-04T10:00:00Z", strategy: .iso8601)
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = try testDatabase()
        } operation: {
            let model = PaymentEntryModel()
            model.selectKind(kind)
            #expect(model.labels.isEmpty)
            model.setNote("Sterilization")
            model.amountText = "100"
            #expect(await model.save())
            model.setNote("ster")
            let deadline = ContinuousClock.now + .seconds(2)
            while model.matchingLabels.isEmpty && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(model.matchingLabels == ["Sterilization"])
        }
    }

    @Test(arguments: [PaymentEntryModel.Kind.consult, .referral])
    func savesExternalReceiptForTodayAndClearsDraft(_ kind: PaymentEntryModel.Kind) async throws {
        let date = try Date("2026-11-04T20:00:00Z", strategy: .iso8601)
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = try testDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var database
            let model = PaymentEntryModel()
            model.selectKind(kind)
            model.setNote("  Visiting clinic  ")
            model.amountText = "1,000"
            model.method = .card

            #expect(await model.save())

            let entries = try await database.read { db in
                try AccountEntryRecord.fetchAll(db).map { try $0.entry() }
            }
            let entry = try #require(entries.first)
            #expect(entries.count == 1)
            #expect(entry.kind == .receipt)
            #expect(entry.patientID == nil)
            #expect(entry.appointmentID == nil)
            #expect(
                entry.category == (kind == .consult ? .externalConsultations : .referralCommissions)
            )
            #expect(entry.note == "Visiting clinic")
            #expect(entry.amount == 1000)
            #expect(entry.paymentMethod == .card)
            #expect(entry.entryDate == FinancialDate.day(date))
            #expect(entry.createdDate == date)
            #expect(model.kind == kind)
            #expect(model.method == .card)
            #expect(model.note.isEmpty)
            #expect(model.amountText.isEmpty)
            #expect(model.patient == nil)
            #expect(model.errorMessage == nil)
            #expect(!model.canAdd)
        }
    }

    @Test(arguments: ["", "0", "-500", "500.50", "abc", "1,0000", String(Int.max) + "0"])
    func invalidAmountsCannotWriteAnEntry(_ text: String) async throws {
        try await withDependencies {
            $0.defaultDatabase = try testDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var database
            let model = PaymentEntryModel()
            model.selectKind(.consult)
            model.setNote("Visiting clinic")
            model.amountText = text
            #expect(await model.save() == false)
            #expect(model.note == "Visiting clinic")
            #expect(model.amountText == text)
            let count = try await database.read { try AccountEntryRecord.count().fetchOne($0) }
            #expect(count == 0)
        }
    }

    @Test func repeatedSaveDoesNotRecordTheSameDraftTwice() async throws {
        let date = try Date("2026-11-05T10:00:00Z", strategy: .iso8601)
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = try testDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var database
            let model = PaymentEntryModel()
            model.selectKind(.consult)
            model.setNote("Visiting clinic")
            model.amountText = "500"
            let first = Task { await model.save() }
            let second = Task { await model.save() }
            let results = await [first.value, second.value]
            #expect(results.filter { $0 }.count == 1)
            #expect(await model.save() == false)
            let count = try await database.read { try AccountEntryRecord.count().fetchOne($0) }
            #expect(count == 1)
        }
    }

    @Test(arguments: [0, 200])
    func patientPaymentSavesMatchingChargeAndReceipt(_ priorBalance: Int) async throws {
        let date = try Date("2026-11-05T10:00:00Z", strategy: .iso8601)
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = try testDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var database
            let patient = Patient(name: "Anjali Desai")
            try await database.write { db in
                try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
            }
            if priorBalance > 0 {
                try await database.createAccountEntry(
                    AccountEntry(details: .adjustment(patientID: patient.id), amount: priorBalance))
            }
            let model = PaymentEntryModel()
            model.selectPatient(patient)
            model.amountText = "500"
            model.method = .cash

            #expect(await model.save())
            #expect(model.errorMessage == nil)
            let balance = try await database.read {
                try currentPatientBalance(patientID: patient.id, in: $0)
            }
            #expect(balance == priorBalance)
            let entries = try await database.read { db in
                try AccountEntryRecord.fetchAll(db).map { try $0.entry() }
                    .filter { $0.kind != .adjustment }
            }
            #expect(entries.count == 2)
            #expect(
                entries.allSatisfy {
                    $0.amount == 500 && $0.entryDate == FinancialDate.day(date)
                        && $0.createdDate == date
                })
            let charge = try #require(entries.first { $0.kind == .charge })
            let receipt = try #require(entries.first { $0.kind == .receipt })
            #expect(charge.details == .charge(patientID: patient.id, appointmentID: nil))
            #expect(
                receipt.details == .receipt(source: .patient(patient.id), paymentMethod: .cash))
            #expect(receipt.note == nil)
            let days = try await database.read { try PaymentDaysRequest(today: date).fetch($0) }
            #expect(days.first?.items.map(\.id) == [receipt.id])
            #expect(days.first?.receipts == 500)
            #expect(model.patient == nil)
            #expect(model.note.isEmpty)
            #expect(model.amountText.isEmpty)
            #expect(model.method == .cash)
        }
    }

    @Test func chargeFailureRollsBackReceiptAndKeepsPatientDraftForRetry() async throws {
        let date = try Date("2026-11-05T10:00:00Z", strategy: .iso8601)
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = try testDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var database
            let patient = Patient(name: "Anjali Desai")
            try await database.write { db in
                try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
                try db.execute(
                    sql: """
                        CREATE TEMP TRIGGER reject_charge BEFORE INSERT ON accountEntries
                        WHEN NEW.kind = 'charge' BEGIN SELECT RAISE(ABORT, 'test failure'); END
                        """)
            }
            let model = PaymentEntryModel()
            model.selectPatient(patient)
            model.amountText = "500"
            model.method = .cash

            #expect(await model.save() == false)
            #expect(model.errorMessage != nil)
            #expect(model.patient?.id == patient.id)
            #expect(model.note == patient.displayName)
            #expect(model.amountText == "500")
            #expect(model.method == .cash)
            #expect(model.canAdd)
            let failedCount = try await database.read {
                try AccountEntryRecord.count().fetchOne($0)
            }
            #expect(failedCount == 0)

            try await database.write { try $0.execute(sql: "DROP TRIGGER reject_charge") }
            model.dismissError()
            #expect(await model.save())
            let savedCount = try await database.read { try AccountEntryRecord.count().fetchOne($0) }
            #expect(savedCount == 2)
        }
    }

    @Test func deletedPatientCannotReceiveAPayment() async throws {
        let date = try Date("2026-11-05T10:00:00Z", strategy: .iso8601)
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = try testDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var database
            let patient = Patient(name: "Anjali Desai")
            try await database.write { db in
                try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
            }
            let model = PaymentEntryModel()
            model.selectPatient(patient)
            model.amountText = "500"
            try await database.write { try PatientRecord.find(patient.id).delete().execute($0) }
            #expect(await model.save() == false)
            #expect(
                model.errorMessage == "This patient is no longer available. Select another patient."
            )
            #expect(model.patient?.id == patient.id)
            #expect(model.amountText == "500")
            let count = try await database.read { try AccountEntryRecord.count().fetchOne($0) }
            #expect(count == 0)
        }
    }

    @Test(arguments: [AccountEntry.PaymentMethod.upi, .cash, .card, .other, nil])
    func savesExpenseWithExistingLabelSpellingAndSelectedMethod(
        _ method: AccountEntry.PaymentMethod?
    ) async throws {
        let date = try Date("2026-11-05T10:00:00Z", strategy: .iso8601)
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = try testDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var database
            try await database.createAccountEntry(
                AccountEntry(
                    details: .expense(category: .materials, paymentMethod: nil), amount: 100,
                    note: "Dental Lab"))
            let model = PaymentEntryModel()
            model.selectKind(.expense)
            model.setNote("  DENTAL LAB  ")
            model.amountText = "500"
            model.method = method
            #expect(await model.save())
            let entry = try await database.read { db in
                try AccountEntryRecord.where { $0.amount.eq(500) }.fetchOne(db)?.entry()
            }
            #expect(
                entry?.details == .expense(category: nil, paymentMethod: method))
            #expect(entry?.note == "Dental Lab")
            let days = try await database.read { try PaymentDaysRequest(today: date).fetch($0) }
            #expect(days.first?.items.count == 2)
            #expect(days.first?.expenses == 600)
            #expect(days.first?.receipts == nil)
        }
    }
}
