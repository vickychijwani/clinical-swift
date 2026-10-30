import ClinicalModels
import ClinicalPersistence
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

#if DEBUG
    @MainActor
    struct SamplePaymentsTests {
        @Test func samplePaymentsAreValidAndSeedOnlyOnce() throws {
            try withDependencies {
                $0.date.now = .now
            } operation: {
                let database = try testDatabase()
                try database.seedSampleDataIfNeeded()
                let entries = try database.read { db in
                    try AccountEntryRecord.all.fetchAll(db).map { try $0.entry() }
                }
                #expect(entries.contains { $0.kind == .receipt && $0.patientID != nil })
                #expect(entries.contains { $0.kind == .receipt && $0.patientID == nil })
                #expect(entries.contains { $0.kind == .expense })
                #expect(entries.contains { $0.amount >= 100000 })
                #expect(entries.contains { $0.paymentMethod == .other })
                #expect(entries.contains { $0.paymentMethod == nil && $0.kind == .receipt })
                for entry in entries {
                    try entry.validate()
                    #expect(entry.entryDate == FinancialDate.day(entry.entryDate))
                }
                try database.seedSampleDataIfNeeded()
                let count = try database.read { try AccountEntryRecord.count().fetchOne($0) }
                #expect(count == entries.count)
            }
        }

        @Test func existingLedgerPreventsPaymentSeeding() throws {
            try withDependencies {
                $0.date.now = .now
            } operation: {
                let database = try testDatabase()
                let entry = AccountEntry(
                    details: .expense(category: .rent, paymentMethod: nil), amount: 100)
                try database.write { db in
                    try saveAccountEntries(AccountEntryBatch(inserts: [entry]), in: db)
                }
                try database.seedSampleDataIfNeeded()
                let count = try database.read { try AccountEntryRecord.count().fetchOne($0) }
                #expect(count == 1)
            }
        }
    }
#endif
