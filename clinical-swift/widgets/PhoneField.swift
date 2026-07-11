import SwiftUI

struct PhoneField: View {
    let label: String
    @Binding var phone: String
    let onPickContact: (String?) -> Void
    let onContactPickerOpened: @MainActor () async -> Void
    @State private var showingContacts = false

    init(
        _ label: String,
        phone: Binding<String>,
        onPickContact: @escaping (String?) -> Void = { _ in },
        onContactPickerOpened: @escaping @MainActor () async -> Void = {}
    ) {
        self.label = label
        self._phone = phone
        self.onPickContact = onPickContact
        self.onContactPickerOpened = onContactPickerOpened
    }

    var body: some View {
        HStack {
            TextField(label, text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .autocorrectionDisabled()

            Button {
                Task {
                    await onContactPickerOpened()
                    showingContacts = true
                }
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Pick contact")
        }
        .sheet(isPresented: $showingContacts) {
            ContactPhonePicker { selectedPhone, contactName in
                phone = PhoneNumber.normalizedE164(selectedPhone) ?? ""
                onPickContact(contactName)
                // No need to set showingContacts to false, dismissal is automatic
            }
        }
    }
}
