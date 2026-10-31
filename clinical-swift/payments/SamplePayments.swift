import ClinicalModels
import ClinicalPersistence
import Foundation
import SQLiteData

#if DEBUG
    extension DatabaseWriter {
        func seedSamplePaymentsIfNeeded() throws {
            @Dependency(\.date.now) var now
            let date = now
            try write { db in
                guard try AccountEntryRecord.count().fetchOne(db) == 0 else { return }
                let patients =
                    try PatientRecord
                    .where { $0.name.eq("Anjali Desai") || $0.name.eq("Priya Narayanan") }
                    .order { $0.name }
                    .fetchAll(db)
                guard patients.count == 2 else { return }
                var entries: [AccountEntry] = []
                for (index, patient) in patients.enumerated() {
                    let amount = index == 0 ? 3200 : 1500
                    entries.append(
                        AccountEntry(
                            details: .charge(patientID: patient.id, appointmentID: nil),
                            amount: amount, entryDate: date, createdDate: date))
                    entries.append(
                        AccountEntry(
                            details: .receipt(
                                source: .patient(patient.id),
                                paymentMethod: index == 0 ? .upi : .card),
                            amount: amount, entryDate: date,
                            createdDate: date.addingTimeInterval(Double(-index))))
                }
                for offset in [1, 3, 4, 7, 14, 30, 90, 400] {
                    guard
                        let day = FinancialDate.calendar.date(
                            byAdding: .day, value: -offset, to: date)
                    else { throw AccountEntryError.invalidFields }
                    entries.append(
                        AccountEntry(
                            details: .expense(
                                category: .materials, paymentMethod: offset == 1 ? .other : .cash),
                            amount: 4800, entryDate: day, createdDate: day,
                            note: offset == 3
                                ? "Dental Craft Laboratory and Advanced Ceramic Restoration Centre"
                                : "Dental Craft Lab"))
                    entries.append(
                        AccountEntry(
                            details: .receipt(
                                source: .externalConsultations,
                                paymentMethod: offset == 4 ? nil : .upi),
                            amount: offset == 7 ? 100000 : 6100, entryDate: day,
                            createdDate: day.addingTimeInterval(-60)))
                }
                try ClinicalPersistence.saveAccountEntries(
                    AccountEntryBatch(inserts: entries), in: db)
            }
        }
    }
#endif
