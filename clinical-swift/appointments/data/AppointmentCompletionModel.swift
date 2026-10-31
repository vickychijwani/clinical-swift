import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData

/// Parsing is strict so invalid pasted text cannot become a different payment or No Dues.
nonisolated enum CompletionAmount {
    static func parse(_ text: String) -> Int? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("₹") {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
        }
        if value.isEmpty { return 0 }
        let groups = value.split(separator: ",", omittingEmptySubsequences: false)
        guard groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(isDigit) }) else { return nil }
        if groups.count > 1 {
            guard groups.last?.count == 3,
                (1...2).contains(groups[0].count),
                groups.dropFirst().dropLast().allSatisfy({ $0.count == 2 })
            else { return nil }
        }
        return Int(groups.joined())
    }

    static func formatted(_ amount: Int) -> String {
        amount.formatted(.number.locale(Locale(identifier: "en_IN")).grouping(.automatic))
    }

    static func isDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }

}

@MainActor @Observable
final class AppointmentCompletionModel: Identifiable {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database

    let id: UUID
    let appointmentID: Appointment.ID
    let patientID: Patient.ID
    let patientName: String
    let originPath: [Route]
    private(set) var amountText = ""
    private(set) var paymentMethod: AccountEntry.PaymentMethod?
    private(set) var isSaving = false
    private(set) var didSave = false
    private(set) var errorMessage: String?

    init(id: UUID, details: AppointmentDetails, originPath: [Route]) {
        self.id = id
        appointmentID = details.appointment.id
        patientID = details.patient.id
        patientName = details.patient.displayName
        self.originPath = originPath
    }

    var amount: Int? { CompletionAmount.parse(amountText) }
    var hasUnsavedChanges: Bool { !amountText.isEmpty || paymentMethod != nil }
    var canSave: Bool { amount != nil && !isSaving && !didSave }
    var buttonTitle: String {
        guard let amount else { return "Complete Appointment" }
        let prefix = amount == 0 ? "No Dues" : "₹\(CompletionAmount.formatted(amount)) Paid"
        return "\(prefix) · Complete Appointment"
    }
    var buttonSymbol: String {
        (amount ?? 0) > 0 ? "indianrupeesign.circle" : "checkmark.circle"
    }

    func setAmountText(_ text: String) {
        guard !isSaving && !didSave, text.filter(CompletionAmount.isDigit).count <= 6 else {
            return
        }
        amountText = text
    }
    func selectMethod(_ method: AccountEntry.PaymentMethod?) {
        guard !isSaving && !didSave else { return }
        paymentMethod = method
    }

    func dismissError() { errorMessage = nil }

    func save() async -> Bool {
        guard canSave, let amount else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await database.completeAppointment(
                id: appointmentID, patientID: patientID, amount: amount,
                paymentMethod: paymentMethod)
            didSave = true
            return true
        } catch let error as AppointmentCompletionError {
            switch error {
            case .unavailable: errorMessage = "This appointment is no longer available."
            case .notScheduled: errorMessage = "This appointment is no longer scheduled."
            case .patientChanged: errorMessage = "The patient for this appointment has changed."
            case .multipleCharges:
                errorMessage =
                    "This appointment has several charges. Complete it after correcting the charges."
            case .invalidAmount: errorMessage = "Enter a valid whole-rupee amount."
            }
        } catch AccountEntryError.negativeBalance {
            errorMessage =
                "This change would leave the patient with a credit balance. Check the earlier receipts."
        } catch {
            errorMessage = "The appointment could not be completed. Please try again."
        }
        return false
    }
}
