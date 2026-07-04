import SwiftUI

struct PhoneField: View {
    let label: String
    @Binding var phone: String
    let onPickContact: (String?) -> Void
    @State private var showingContacts = false

    init(
        _ label: String,
        phone: Binding<String>,
        onPickContact: @escaping (String?) -> Void = { _ in }
    ) {
        self.label = label
        self._phone = phone
        self.onPickContact = onPickContact
    }

    var body: some View {
        HStack {
            TextField(label, text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .autocorrectionDisabled()

            Button {
                showingContacts = true
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Pick contact")
        }
        .sheet(isPresented: $showingContacts) {
            ContactPhonePicker { selectedPhone, contactName in
                phone = selectedPhone
                onPickContact(contactName)
                // No need to set showingContacts to false, dismissal is automatic
            }
        }
    }
}
