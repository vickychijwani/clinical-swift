import ClinicalModels
import Dependencies
import Foundation
import MessageUI

@MainActor @Observable
final class AppointmentMessageModel {
    @ObservationIgnored @Dependency(\.appointmentMessagingClient) private var messagingClient
    @ObservationIgnored @Dependency(\.appointmentContactClient) private var contactClient
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.telemetry) private var telemetry

    let details: AppointmentDetails
    let includesLocation: Bool

    var kind: AppointmentMessageKind = .confirmation {
        didSet {
            guard oldValue != kind else { return }
            regenerateMessage()
        }
    }
    var message = ""
    var errorMessage: String?
    var smsDraft: AppointmentSMSDraft?
    private(set) var recipientPhone: String?
    private(set) var recipientName: String?
    private(set) var isSavingRecipient = false
    private var patient: Patient

    var hasValidRecipientPhone: Bool {
        PhoneNumber.normalizedE164(recipientPhone) != nil
    }

    var recipientLabel: String {
        recipientName
            ?? PhoneNumber.formattedForDisplay(recipientPhone)
            ?? "Choose contact"
    }

    var recipientSystemImage: String {
        recipientName == nil && hasValidRecipientPhone ? "phone" : "person"
    }

    init(details: AppointmentDetails, includesLocation: Bool) {
        self.details = details
        self.includesLocation = includesLocation
        self.patient = details.patient
        recipientPhone = PhoneNumber.normalizedE164(details.patient.phone)
        regenerateMessage()
    }

    func loadRecipientName() async {
        guard recipientName == nil, let recipientPhone else { return }
        recipientName = await contactClient.nameForPhone(recipientPhone)
    }

    @discardableResult
    func selectRecipient(phone: String, name: String?) async -> PatientPhoneSaveResult {
        guard !isSavingRecipient else { return .unchanged }
        isSavingRecipient = true
        defer { isSavingRecipient = false }

        let result = await PatientEditorModel.savePhone(phone, for: patient)
        switch result {
        case .saved(let savedPatient):
            patient = savedPatient
            recipientPhone = savedPatient.phone
            recipientName = name?.nilIfBlank
            errorMessage = nil
        case .unchanged:
            if let normalizedPhone = PhoneNumber.normalizedE164(phone) {
                recipientPhone = normalizedPhone
            }
            recipientName = name?.nilIfBlank
            errorMessage = nil
        case .invalidPhone, .failed:
            break
        }
        return result
    }

    func regenerateMessage() {
        message = AppointmentMessageFormatter(
            kind: kind,
            details: details,
            includesLocation: includesLocation,
            now: now,
            calendar: ClinicDate.calendar
        )
        .message()
    }

    func startSend() {
        errorMessage = nil

        messagingClient.copy(message)

        guard let phone = recipientPhone,
            let phoneDigits = PhoneNumber.whatsAppDigits(phone)
        else {
            errorMessage =
                "The message was copied, but this patient does not have a usable phone number."
            telemetry.log(
                .warning,
                category: .appointment,
                name: "appointment_message_blocked",
                message: errorMessage,
                recordID: details.appointment.id.uuidString.lowercased(),
                status: "missing_phone",
                action: kind.rawValue
            )
            return
        }

        guard messagingClient.canSendText() else {
            errorMessage = "The message was copied, but SMS is not available on this device."
            telemetry.log(
                .warning,
                category: .appointment,
                name: "appointment_message_blocked",
                message: errorMessage,
                recordID: details.appointment.id.uuidString.lowercased(),
                status: "sms_unavailable",
                action: kind.rawValue
            )
            return
        }

        telemetry.event(
            category: .appointment,
            name: "appointment_message_started",
            recordID: details.appointment.id.uuidString.lowercased(),
            action: kind.rawValue
        )
        smsDraft = AppointmentSMSDraft(
            recipient: phone,
            phoneDigits: phoneDigits,
            body: message
        )
    }

    func finishSMS(with result: MessageComposeResult) -> AppointmentWhatsAppRequest? {
        guard let smsDraft else { return nil }
        self.smsDraft = nil

        switch result {
        case .sent:
            telemetry.event(
                category: .appointment,
                name: "appointment_sms_sent",
                recordID: details.appointment.id.uuidString.lowercased(),
                status: "sent",
                action: kind.rawValue
            )
            return AppointmentWhatsAppRequest(
                phoneDigits: smsDraft.phoneDigits,
                message: smsDraft.body
            )
        case .cancelled:
            telemetry.event(
                category: .appointment,
                name: "appointment_sms_cancelled",
                recordID: details.appointment.id.uuidString.lowercased(),
                status: "cancelled",
                action: kind.rawValue
            )
            return nil
        case .failed:
            errorMessage = "The message was copied, but SMS could not be sent."
            telemetry.log(
                .error,
                category: .appointment,
                name: "appointment_sms_failed",
                message: errorMessage,
                recordID: details.appointment.id.uuidString.lowercased(),
                status: "failed",
                action: kind.rawValue
            )
            return nil
        @unknown default:
            errorMessage = "The message was copied, but SMS ended unexpectedly."
            telemetry.log(
                .error,
                category: .appointment,
                name: "appointment_sms_failed",
                message: errorMessage,
                recordID: details.appointment.id.uuidString.lowercased(),
                status: "unknown",
                action: kind.rawValue
            )
            return nil
        }
    }

    func openWhatsApp(_ request: AppointmentWhatsAppRequest) async -> Bool {
        let didOpen = await messagingClient.openWhatsApp(request.phoneDigits, request.message)
        if didOpen {
            telemetry.event(
                category: .appointment,
                name: "appointment_whatsapp_opened",
                recordID: details.appointment.id.uuidString.lowercased(),
                status: "opened",
                action: kind.rawValue
            )
        } else {
            errorMessage = "SMS was sent, but WhatsApp could not be opened."
            telemetry.log(
                .warning,
                category: .appointment,
                name: "appointment_whatsapp_failed",
                message: errorMessage,
                recordID: details.appointment.id.uuidString.lowercased(),
                status: "failed",
                action: kind.rawValue
            )
        }
        return didOpen
    }
}

nonisolated struct AppointmentSMSDraft: Identifiable, Equatable, Sendable {
    let id = UUID()
    let recipient: String
    let phoneDigits: String
    let body: String
}

nonisolated struct AppointmentWhatsAppRequest: Equatable, Sendable {
    let phoneDigits: String
    let message: String
}
