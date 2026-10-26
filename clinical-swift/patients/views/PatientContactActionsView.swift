import ClinicalModels
import SwiftUI

struct PatientContactActionsView: View {
    @Environment(\.openURL) private var openURL

    let patient: Patient

    var body: some View {
        HStack {
            Button("Call", systemImage: "phone.fill", action: callPatient)
                .disabled(telURL == nil)

            Button(
                "WhatsApp",
                systemImage: "message.fill",
                action: openWhatsAppChat
            )
            .disabled(whatsappURL == nil)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(AppColor.icon)
    }

    private var normalizedPhoneNumber: String? {
        PhoneNumber.normalizedE164(patient.phone)
    }

    private var telURL: URL? {
        guard let normalizedPhoneNumber else { return nil }
        return URL(string: "tel://\(normalizedPhoneNumber)")
    }

    private var whatsappURL: URL? {
        guard let phoneNumber = normalizedPhoneNumber?.filter(\.isNumber) else {
            return nil
        }
        return URL(string: "https://wa.me/\(phoneNumber)")
    }

    private func callPatient() {
        guard let telURL else { return }
        openURL(telURL)
    }

    private func openWhatsAppChat() {
        guard let whatsappURL else { return }
        openURL(whatsappURL)
    }
}
