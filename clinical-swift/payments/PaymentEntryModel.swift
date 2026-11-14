import ClinicalModels
import ClinicalPersistence
import Foundation
import SQLiteData

@MainActor @Observable
final class PaymentEntryModel {
    enum Kind: String, CaseIterable {
        case patient = "Patient"
        case consult = "Consult"
        case referral = "Referral"
        case expense = "Expense"

        var placeholder: String {
            switch self {
            case .patient: "Search patient by name"
            case .consult: "Consultation label"
            case .referral: "Referral label"
            case .expense: "Expense label"
            }
        }

        func includes(_ entry: AccountEntryRecord) -> Bool {
            switch self {
            case .patient: false
            case .consult:
                entry.kind == "receipt" && entry.category == "externalConsultations"
            case .referral:
                entry.kind == "receipt" && entry.category == "referralCommissions"
            case .expense: entry.kind == "expense"
            }
        }
    }

    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored var patientRows = FetchAll<PatientDetailsSelection>()
    @ObservationIgnored
    @FetchAll(AccountEntryRecord.where { $0.note.isNot(nil) }.order { $0.createdAt.desc() })
    private var previousEntries: [AccountEntryRecord] = []

    private(set) var kind = Kind.patient
    private(set) var note = ""
    private(set) var patient: Patient?
    var amountText = ""
    var method: AccountEntry.PaymentMethod? = .upi
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    var patients: [Patient] {
        let patients = patientRows.wrappedValue.map { $0.details.patient }
        guard let query = note.nilIfBlank else { return patients }
        return patients.filter { PatientNameSearch.matches($0.name, searchText: query) }
    }

    var labels: [String] {
        Self.labels(for: kind, entries: previousEntries)
    }

    var matchingLabels: [String] {
        guard let query = note.nilIfBlank else { return labels }
        return labels.filter { $0.localizedStandardContains(query) }
    }

    var canAdd: Bool {
        guard !isSaving else { return false }
        guard let amount = CompletionAmount.parse(amountText), amount > 0 else { return false }
        return kind == .patient ? patient != nil : note.nilIfBlank != nil
    }

    func loadPatients() async {
        _ = try? await patientRows.load(appointmentBookingPatientRowsQuery(now: now))
    }

    func selectKind(_ kind: Kind) {
        guard !isSaving, self.kind != kind else { return }
        self.kind = kind
        note = ""
        patient = nil
    }

    func setNote(_ text: String) {
        guard !isSaving else { return }
        // TextField can send the selected name back through its binding without an edit.
        guard note != text else { return }
        note = text
        patient = nil
    }

    func selectPatient(_ patient: Patient) {
        guard !isSaving else { return }
        self.patient = patient
        note = patient.displayName
    }

    func selectLabel(_ label: String) {
        guard !isSaving else { return }
        note = label
    }

    func finishNote() {
        guard !isSaving, kind != .patient, let value = note.nilIfBlank else { return }
        note = labels.first { $0.localizedCaseInsensitiveCompare(value) == .orderedSame } ?? value
    }

    func dismissError() { errorMessage = nil }

    func save() async -> Bool {
        guard canAdd, let amount = CompletionAmount.parse(amountText) else { return false }
        finishNote()
        let details: AccountEntry.Details
        switch kind {
        case .patient:
            guard let patient else { return false }
            details = .receipt(source: .patient(patient.id), paymentMethod: method)
        case .consult:
            details = .receipt(source: .externalConsultations, paymentMethod: method)
        case .referral:
            details = .receipt(source: .referralCommissions, paymentMethod: method)
        case .expense:
            details = .expense(category: nil, paymentMethod: method)
        }
        let timestamp = now
        var entries = [
            AccountEntry(
                details: details, amount: amount, entryDate: timestamp, createdDate: timestamp,
                note: kind == .patient ? nil : note)
        ]
        if case .receipt(.patient(let patientID), _) = details {
            // Insert the receipt first so a large balance cannot overflow before it returns to its prior value.
            entries.append(
                AccountEntry(
                    details: .charge(patientID: patientID, appointmentID: nil), amount: amount,
                    entryDate: timestamp, createdDate: timestamp))
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await database.saveAccountEntries(.init(inserts: entries))
            note = ""
            patient = nil
            amountText = ""
            return true
        } catch AccountEntryError.missingPatient {
            errorMessage = "This patient is no longer available. Select another patient."
        } catch {
            errorMessage = "The payment could not be saved. Please try again."
        }
        return false
    }

    static func labels(for kind: Kind, entries: [AccountEntryRecord]) -> [String] {
        var labels: [String] = []
        for entry in entries where kind.includes(entry) {
            guard let label = entry.note?.nilIfBlank,
                !labels.contains(where: {
                    $0.localizedCaseInsensitiveCompare(label) == .orderedSame
                })
            else { continue }
            labels.append(label)
        }
        return labels
    }
}
