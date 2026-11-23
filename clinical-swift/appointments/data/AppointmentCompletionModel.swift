import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData

@MainActor @Observable
final class AppointmentCompletionModel: Identifiable {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.telemetry) private var telemetry

    let id: UUID
    let appointmentID: Appointment.ID
    let patient: Patient
    var patientID: Patient.ID { patient.id }
    var patientName: String { patient.displayName }
    let originPath: [Route]
    private(set) var amountText = ""
    private(set) var paymentMethod: AccountEntry.PaymentMethod?
    private(set) var isSaving = false
    private(set) var didSave = false
    private(set) var errorMessage: String?

    init(id: UUID, details: AppointmentDetails, originPath: [Route]) {
        self.id = id
        appointmentID = details.appointment.id
        patient = details.patient
        self.originPath = originPath
    }

    var amount: Int? { RupeeAmount.parse(amountText, emptyAsZero: true) }
    var hasUnsavedChanges: Bool { !amountText.isEmpty || paymentMethod != nil }
    var canSave: Bool { amount != nil && !isSaving && !didSave }
    var buttonTitle: String {
        guard let amount else { return "Complete Appointment" }
        let prefix = amount == 0 ? "No Dues" : "₹\(RupeeAmount.formatted(amount)) Paid"
        return "\(prefix) · Complete Appointment"
    }
    var buttonSymbol: String {
        (amount ?? 0) > 0 ? "indianrupeesign.circle" : "checkmark.circle"
    }

    func setAmountText(_ text: String) {
        guard !isSaving && !didSave, text.filter(RupeeAmount.isDigit).count <= 6 else {
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
            telemetry.event(
                category: .appointment,
                name: "appointment_completed",
                recordID: appointmentID.uuidString.lowercased(),
                status: amount == 0 ? "no_dues" : "paid",
                action: paymentMethod?.rawValue
            )
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
            telemetry.log(
                .error,
                category: .appointment,
                name: "appointment_completion_failed",
                message: errorMessage,
                error: error,
                recordID: appointmentID.uuidString.lowercased()
            )
        } catch AccountEntryError.negativeBalance(let patientID) {
            errorMessage =
                "This change would leave the patient with a credit balance. Check the earlier receipts."
            telemetry.log(
                .error,
                category: .appointment,
                name: "appointment_completion_failed",
                message: errorMessage,
                error: AccountEntryError.negativeBalance(patientID),
                recordID: appointmentID.uuidString.lowercased()
            )
        } catch {
            errorMessage = "The appointment could not be completed. Please try again."
            telemetry.log(
                .error,
                category: .appointment,
                name: "appointment_completion_failed",
                message: errorMessage,
                error: error,
                recordID: appointmentID.uuidString.lowercased()
            )
        }
        return false
    }
}
