import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData
import Testing

private nonisolated enum PaymentListFixture {
    static func date(_ value: String) throws -> Date { try Date(value, strategy: .iso8601) }

    static func item(
        _ details: AccountEntry.Details = .expense(category: .materials, paymentMethod: nil),
        amount: Int = 4800, date: String = "2026-10-24T12:00:00Z",
        recorded: String = "2026-10-24T12:00:00Z", id: UUID = UUID(),
        note: String? = nil, patientName: String? = nil
    ) throws -> PaymentItem {
        PaymentItem(
            entry: AccountEntry(
                id: id, details: details, amount: amount, entryDate: try self.date(date),
                createdDate: try self.date(recorded), note: note),
            patientName: patientName)
    }
}

struct PaymentListTests {
    @Test func titlesAndMethodsUseOnlyTheSpecifiedFields() throws {
        let patientID = UUID()
        let patient = try PaymentListFixture.item(
            .receipt(source: .patient(patientID), paymentMethod: .upi),
            note: "Do not use this note", patientName: "Priya Ramaswamy")
        #expect(patient.title == "Priya Ramaswamy")
        #expect(patient.method == "UPI")
        for name in [nil, "", " \n"] as [String?] {
            #expect(
                try PaymentListFixture.item(
                    .receipt(source: .patient(patientID), paymentMethod: nil),
                    patientName: name
                ).title == "Unknown Patient")
        }
        #expect(
            try PaymentListFixture.item(note: "  Dental Craft Lab \n").title == "Dental Craft Lab")
        #expect(try PaymentListFixture.item(note: " \n").title == "Materials")
        #expect(
            try PaymentListFixture.item(
                .receipt(source: .externalConsultations, paymentMethod: nil)
            ).title == "External consultations")
        #expect(
            try PaymentListFixture.item(
                .charge(patientID: patientID, appointmentID: nil)
            ).title == "Unknown")
        for method in AccountEntry.PaymentMethod.allCases {
            let row = try PaymentListFixture.item(.expense(category: .rent, paymentMethod: method))
            #expect(row.method == [.cash: "Cash", .upi: "UPI", .card: "Card"][method])
            #expect(row.entry.paymentMethod == method)
        }
        #expect(try PaymentListFixture.item().method == nil)
        for category in AccountEntry.ExpenseCategory.allCases {
            let row = try PaymentListFixture.item(.expense(category: category, paymentMethod: nil))
            #expect(!row.title.isEmpty && row.title != "Unknown")
        }
    }

    @Test func amountFormattingKeepsExactWholeRupeesAndIndianGroups() {
        #expect(PaymentItem.amount(3200, isReceipt: true) == "+₹3,200")
        #expect(PaymentItem.amount(4800, isReceipt: false) == "−₹4,800")
        #expect(PaymentItem.amount(100000, isReceipt: true) == "+₹1,00,000")
        #expect(PaymentItem.amount(Int.max, isReceipt: true) == "+₹92,23,37,20,36,85,47,75,807")
    }

    @Test func relativeDatesUseClinicMidnightAndClinicYear() throws {
        let before = try PaymentListFixture.date("2026-12-31T18:29:59Z")
        let after = try PaymentListFixture.date("2026-12-31T18:30:00Z")
        var deviceCalendar = Calendar(identifier: .buddhist)
        deviceCalendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        withDependencies {
            $0.calendar = deviceCalendar
            $0.locale = Locale(identifier: "ar_SA")
        } operation: {
            #expect(PaymentDay.title(for: before, today: before) == "Today")
            #expect(PaymentDay.title(for: before, today: after) == "Yesterday")
            #expect(PaymentDay.title(for: after, today: after) == "Today")
        }
        let april = try PaymentListFixture.date("2026-04-17T12:00:00Z")
        #expect(PaymentDay.title(for: april, today: before) == "Fri, 17 Apr")
        #expect(PaymentDay.title(for: april, today: after) == "Fri, 17 Apr 2026")
        #expect(
            PaymentDay.title(
                for: try PaymentListFixture.date("2025-04-17T12:00:00Z"), today: after)
                == "Thu, 17 Apr 2025")
    }

    @Test func orderingAndTotalsUseDatesThenRecordingDatesThenIDs() throws {
        let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let receipt = try PaymentListFixture.item(
            .receipt(source: .otherReceipts, paymentMethod: .cash), amount: 100000)
        let lower = try PaymentListFixture.item(id: lowID)
        let higher = try PaymentListFixture.item(id: highID)
        let later = try PaymentListFixture.item(recorded: "2026-10-24T13:00:00Z")
        let older = try PaymentListFixture.item(
            date: "2025-01-01T12:00:00Z", recorded: "2026-10-24T14:00:00Z")
        let charge = try PaymentListFixture.item(.charge(patientID: UUID(), appointmentID: nil))
        let adjustment = try PaymentListFixture.item(.adjustment(patientID: UUID()))
        let days = try PaymentDay.sections(
            from: [lower, older, higher, receipt, charge, later, adjustment],
            today: PaymentListFixture.date("2026-10-24T12:00:00Z"))
        let first = try #require(days.first)
        #expect(first.items.first?.id == later.id)
        #expect(
            first.items.filter { [lowID, highID].contains($0.id) }.map(\.id) == [highID, lowID])
        #expect(first.receipts == 100000)
        #expect(first.expenses == 14400)
        #expect(days.last?.items == [older])
        #expect(days.last?.receipts == nil)
        #expect(days.flatMap(\.items).count == 5)
    }

    @Test func emptyDaysStopAtEarliestPaymentAndOmitOnlyEmptySundays() throws {
        let saturday = try PaymentListFixture.item()
        let ignored = try PaymentListFixture.item(
            .charge(patientID: UUID(), appointmentID: nil), date: "2026-10-01T12:00:00Z")
        let tuesday = try PaymentListFixture.date("2026-10-27T12:00:00Z")
        let days = try PaymentDay.sections(from: [saturday, ignored], today: tuesday)
        #expect(days.map(\.title) == ["Today", "Yesterday", "Sat, 24 Oct"])
        #expect(
            days.prefix(2).allSatisfy {
                $0.items.isEmpty && $0.receipts == nil && $0.expenses == nil
            })
        let sunday = try PaymentListFixture.date("2026-10-25T12:00:00Z")
        #expect(
            try PaymentDay.sections(from: [saturday], today: sunday).map(\.title) == ["Yesterday"])
        for details: AccountEntry.Details in [
            .receipt(source: .otherReceipts, paymentMethod: nil),
            .expense(category: .rent, paymentMethod: nil),
        ] {
            let payment = try PaymentListFixture.item(details, date: "2026-10-25T18:29:59Z")
            let changed = try PaymentDay.sections(from: [saturday, payment], today: tuesday)
            #expect(changed.count == 4)
            #expect(changed[2].items == [payment])
        }
        let midnight = try PaymentListFixture.item(date: "2026-10-25T18:30:00Z")
        #expect(FinancialDate.day(midnight.entry.entryDate) == days[1].id)
    }

    @Test func totalsFailOnOverflowRatherThanDroppingAnEntry() throws {
        for details: AccountEntry.Details in [
            .receipt(source: .otherReceipts, paymentMethod: nil),
            .expense(category: .equipmentPurchases, paymentMethod: nil),
        ] {
            let items = try [
                PaymentListFixture.item(details, amount: Int.max),
                PaymentListFixture.item(details, amount: 1),
            ]
            #expect(throws: AccountEntryError.overflow) {
                try PaymentDay.sections(from: items, today: PaymentsFixture.now)
            }
        }
    }

    @Test func observedHistoryTracksWritesRenamesDeletesAndSundayVisibility() async throws {
        let database = try PaymentsFixture.database()
        let sunday = try PaymentListFixture.date("2026-10-25T12:00:00Z")
        try await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = sunday
        } operation: {
            let charge = PaymentsFixture.entry(.charge, 100)
            let receipt = PaymentsFixture.entry(.receipt, 50)
            try await database.saveAccountEntries(AccountEntryBatch(inserts: [charge, receipt]))
            @Fetch(PaymentDaysRequest(today: sunday)) var days: [PaymentDay] = []
            try await $days.load()
            #expect(days.count == 1)
            #expect(days.first?.items.map(\.id) == [receipt.id])
            let expense = try PaymentListFixture.item(date: "2026-10-25T12:00:00Z").entry
            try await database.createAccountEntry(expense)
            for _ in 0..<200 {
                if days.count == 2 { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(days.first?.title == "Today")
            #expect(days.first?.expenses == 4800)
            try await database.write { db in
                try PatientRecord.find(PaymentsFixture.patientID).update {
                    $0.name = #bind("Renamed Patient")
                }.execute(db)
            }
            for _ in 0..<200 {
                if days.last?.items.first?.title == "Renamed Patient" { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(days.last?.items.first?.title == "Renamed Patient")
            var edited = expense
            edited.amount = 6000
            try await database.editAccountEntry(edited)
            for _ in 0..<200 {
                if days.first?.expenses == 6000 { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(days.first?.expenses == 6000)
            try await database.deleteAccountEntry(id: expense.id)
            for _ in 0..<200 {
                if days.count == 1 { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(days.count == 1)
            #expect(days.first?.receipts == 50)
            #expect(days.first?.expenses == nil)
            try await $days.load(PaymentDaysRequest(today: FinancialDate.nextDay(sunday)))
            #expect(days.first?.title == "Today")
            #expect(days.first?.items.isEmpty == true)
        }
    }
}
