import SwiftUI

struct EditPatientView: View {
    @Environment(\.dismiss) private var dismiss

    @State var name: String?
    @State var phone: String?
    @State var dob: Date?
    @State var gender: Gender?

    var body: some View {
        Form {
            TextField("Name", text: $name.replacingNil())
                .textContentType(.name)
                .autocorrectionDisabled()

            PhoneField("Phone number", phone: $phone.replacingNil())

            DatePicker("Date of birth",
                       selection: $dob.replacingNil(),
                       in: ...Date(),
                       displayedComponents: .date)

            Picker("Gender", selection: $gender) {
                Text("Not specified")
                    .tag(nil as Gender?)
                Text(Gender.male.displayName)
                    .tag(Gender.male)
                Text(Gender.female.displayName)
                    .tag(Gender.female)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Edit Patient")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Label("Done", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    print("Save patient")
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        EditPatientView()
            .background(Color("AppBackground"))
    }
}
