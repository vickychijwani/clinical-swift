import SwiftUI

struct PhoneField: View {
    let label: String
    @Binding var phone: String
    @State private var showingContacts = false

    init(_ label: String, phone: Binding<String>) {
        self.label = label
        self._phone = phone
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
            ContactPhonePicker { selectedPhone in
                phone = selectedPhone
                showingContacts = false
            }
        }
    }
}
