import SQLiteData
import SwiftUI

struct EditPatientView: View {
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.defaultDatabase) private var database

    @State var name: String?
    @State var phone: String?
    @State var dob: Date?
    @State var gender: Gender?
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

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

            LabeledContent("Gender") {
                Picker("Gender", selection: $gender) {
                    Text("M")
                        .tag(Gender.male as Gender?)
                    Text("F")
                        .tag(Gender.female as Gender?)
                    Text("Other")
                        .tag(Gender.other as Gender?)
                }
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)
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
                    savePatient()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                }
                .disabled(isSaving)
            }
        }
        .alert(
            "Unable to save patient",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private func savePatient() {
        let patient = Patient(
            id: UUID(),
            name: name?.nilIfBlank,
            phone: phone?.nilIfBlank,
            dob: dob,
            gender: gender
        )

        do {
            try patient.validate()
        } catch Patient.ValidationError.missingNameAndPhone {
            saveErrorMessage = "Enter a name or phone number."
            return
        } catch {
            saveErrorMessage = "Check the patient details and try again."
            return
        }

        isSaving = true
        Task {
            do {
                try await database.write { db in
                    try PatientRecord.insert { PatientRecord(patient) }
                        .execute(db)
                }
                dismiss()
            } catch {
                saveErrorMessage = "The patient could not be saved."
            }
            isSaving = false
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    NavigationStack {
        EditPatientView()
            .background(Color("AppBackground"))
    }
}
