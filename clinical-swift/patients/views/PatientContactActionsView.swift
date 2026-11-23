import ClinicalModels
import SwiftUI

struct PatientContactActionsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(ToastStore.self) private var toast: ToastStore?

    @State private var isPickingContact = false
    @State private var isSavingContact = false

    let patient: Patient

    var body: some View {
        Group {
            if normalizedPhoneNumber != nil {
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
            } else {
                Button("Add contact") {
                    isPickingContact = true
                }
                .buttonStyle(.glass)
                .controlSize(.mini)
                .fixedSize()
                .disabled(isSavingContact)
            }
        }
        .sheet(isPresented: $isPickingContact) {
            ContactPhonePicker { phone, _ in
                Task {
                    await savePickedContact(phone)
                }
                // No need to set isPickingContact to false, dismissal is automatic
            }
            .ignoresSafeArea()
        }
    }

    private func savePickedContact(_ phone: String) async {
        guard !isSavingContact else { return }
        isSavingContact = true
        defer { isSavingContact = false }

        switch await PatientEditorModel.savePhone(phone, for: patient) {
        case .saved, .unchanged:
            break
        case .invalidPhone:
            toast?.show(message: "Invalid phone number")
        case .failed:
            toast?.show(message: "Save failed")
        }
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
