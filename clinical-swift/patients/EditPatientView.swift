import SQLiteData
import SwiftUI

struct EditPatientView: View {
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.defaultDatabase) private var database

    private let originalDraft: PatientDraft

    @State private var draft: PatientDraft
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(patient: Patient? = nil) {
        let draft = PatientDraft(patient: patient)
        self.originalDraft = draft.normalized
        self._draft = State(initialValue: draft)
    }

    var body: some View {
        ConfirmingFormSheet(
            hasUnsavedChanges: hasUnsavedChanges,
            title: "Discard unsaved changes?",
            message: "Your patient details have not been saved."
        ) { guardedDismiss in
            EditPatientForm(
                draft: $draft,
                isSaving: isSaving,
                saveErrorMessage: $saveErrorMessage,
                guardedDismiss: guardedDismiss,
                savePatient: savePatient
            )
        }
    }

    private var hasUnsavedChanges: Bool {
        draft.normalized != originalDraft
    }

    private func savePatient() {
        let patient = draft.makePatient()

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

private struct EditPatientForm: View {
    @Binding var draft: PatientDraft
    @Binding var saveErrorMessage: String?
    let isSaving: Bool
    let guardedDismiss: FormSheetDismissAction
    let savePatient: () -> Void

    @State private var isPickingDOB = false
    @State private var draftDOB = Date()

    init(
        draft: Binding<PatientDraft>,
        isSaving: Bool,
        saveErrorMessage: Binding<String?>,
        guardedDismiss: FormSheetDismissAction,
        savePatient: @escaping () -> Void
    ) {
        self._draft = draft
        self.isSaving = isSaving
        self._saveErrorMessage = saveErrorMessage
        self.guardedDismiss = guardedDismiss
        self.savePatient = savePatient
    }

    var body: some View {
        Form {
            TextField("Name", text: $draft.name.replacingNil())
                .textContentType(.name)
                .autocorrectionDisabled()
            PhoneField("Phone number", phone: $draft.phone.replacingNil())

            PatientDOBField(
                title: "Date of birth",
                selection: $draft.dob,
                isPickingDOB: $isPickingDOB,
                draftDOB: $draftDOB
            )

            PatientGenderField(title: "Gender", selection: $draft.gender)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Edit Patient")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    guardedDismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark")
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
        .sheet(isPresented: $isPickingDOB) {
            PatientDOBPicker(dob: $draft.dob, draftDOB: $draftDOB, isPresented: $isPickingDOB)
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
}

private struct PatientDOBField: View {
    let title: String
    @Binding var selection: Date?
    @Binding var isPickingDOB: Bool
    @Binding var draftDOB: Date

    var body: some View {
        Button {
            draftDOB = selection ?? Date()
            isPickingDOB = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                Text(selection?.formatted(.dateTime.day().month().year()) ?? "Add")
                    .foregroundStyle(selection == nil ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PatientDOBPicker: View {
    @Binding var dob: Date?
    @Binding var draftDOB: Date
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            DatePicker(
                "Date of birth",
                selection: $draftDOB,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding()
            .navigationTitle("Date of birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dob = draftDOB
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.height(250)])
    }
}

private struct PatientGenderField: View {
    let title: String
    @Binding var selection: Gender?

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection) {
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
