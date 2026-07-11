import Dependencies
import Foundation
import MessageUI

@MainActor @Observable
final class AppointmentMessageModel {
    @ObservationIgnored @Dependency(\.appointmentMessagingClient) private var messagingClient
    @ObservationIgnored @Dependency(\.appointmentContactClient) private var contactClient
    @ObservationIgnored @Dependency(\.calendar) private var calendar
    @ObservationIgnored @Dependency(\.date.now) private var now

    let details: AppointmentDetails
    let includesLocation: Bool

    var kind: AppointmentMessageKind = .confirmation {
        didSet {
            guard oldValue != kind else { return }
            regenerateMessage()
        }
    }
    var includesPatientName = true {
        didSet {
            guard oldValue != includesPatientName else { return }
            regenerateMessage()
        }
    }
    var message = ""
    var errorMessage: String?
    var smsDraft: AppointmentSMSDraft?
    private(set) var recipientPhone: String?
    private(set) var recipientName: String?

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
        recipientPhone = PhoneNumber.normalizedE164(details.patient.phone)
        regenerateMessage()
    }

    func loadRecipientName() async {
        guard recipientName == nil, let recipientPhone else { return }
        recipientName = await contactClient.nameForPhone(recipientPhone)
    }

    func selectRecipient(phone: String, name: String?) {
        guard let normalizedPhone = PhoneNumber.normalizedE164(phone) else { return }
        recipientPhone = normalizedPhone
        recipientName = name?.nilIfBlank
        errorMessage = nil
    }

    func regenerateMessage() {
        message = AppointmentMessageFormatter(
            kind: kind,
            details: details,
            includesPatientName: includesPatientName,
            includesLocation: includesLocation,
            now: now,
            calendar: calendar
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
            return
        }

        guard messagingClient.canSendText() else {
            errorMessage = "The message was copied, but SMS is not available on this device."
            return
        }

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
            return AppointmentWhatsAppRequest(
                phoneDigits: smsDraft.phoneDigits,
                message: smsDraft.body
            )
        case .cancelled:
            return nil
        case .failed:
            errorMessage = "The message was copied, but SMS could not be sent."
            return nil
        @unknown default:
            errorMessage = "The message was copied, but SMS ended unexpectedly."
            return nil
        }
    }

    func openWhatsApp(_ request: AppointmentWhatsAppRequest) async -> Bool {
        let didOpen = await messagingClient.openWhatsApp(request.phoneDigits, request.message)
        if !didOpen {
            errorMessage = "SMS was sent, but WhatsApp could not be opened."
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
