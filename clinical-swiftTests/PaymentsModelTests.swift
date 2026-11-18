import ClinicalModels
import ClinicalPersistence
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct PaymentsModelTests {
    @Test func selectionFiltersHistoryAndReturningToAllRestoresIt() async throws {
        let date = try Date("2026-11-04T10:00:00Z", strategy: .iso8601)
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = try testDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var database
            let receipt = AccountEntry(
                details: .receipt(source: .otherIncome, paymentMethod: .cash), amount: 1200)
            let expense = AccountEntry(
                details: .expense(category: .materials, paymentMethod: nil), amount: 500)
            try await database.write { db in
                try saveAccountEntries(AccountEntryBatch(inserts: [receipt, expense]), in: db)
            }
            let model = PaymentsModel()
            try await model.$days.load()
            let allDays = model.days
            #expect(model.filter == .all)
            #expect(model.filteredDays == allDays)
            #expect(model.filteredDays.flatMap(\.items).count == 2)

            model.filter = .incoming
            #expect(model.filteredDays.flatMap(\.items).map(\.id) == [receipt.id])
            #expect(model.filteredDays.first?.receipts == 1200)
            #expect(model.filteredDays.first?.expenses == nil)

            model.filter = .outgoing
            #expect(model.filteredDays.flatMap(\.items).map(\.id) == [expense.id])
            #expect(model.filteredDays.first?.receipts == nil)
            #expect(model.filteredDays.first?.expenses == 500)

            model.filter = .all
            #expect(model.filteredDays == allDays)
            #expect(model.days == allDays)
        }
    }
}
