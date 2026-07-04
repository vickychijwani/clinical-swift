import SQLiteData
import SwiftUI

struct EditPatientView: View {
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.defaultDatabase) private var database

    private let originalDraft: PatientDraft

    @State private var draft: PatientDraft
    @State private var saveErrorMessage: String?

    init(patient: Patient? = nil) {
        let draft = PatientDraft(patient: patient)
        self.originalDraft = draft.normalized
        self._draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            ConfirmingFormSheet(
                hasUnsavedChanges: hasUnsavedChanges,
                title: "Discard unsaved changes?",
                message: "Your patient details have not been saved."
            ) { guardedDismiss in
                EditPatientForm(
                    draft: $draft,
                    saveErrorMessage: $saveErrorMessage,
                    guardedDismiss: guardedDismiss,
                    savePatient: savePatient
                )
            }
        }
        .modifier(FittedSheetModifier(fitsVertically: true))
        .background(Color("AppBackground"))
    }

    private var hasUnsavedChanges: Bool {
        draft.normalized != originalDraft
    }

    private func savePatient() async {
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

        do {
            try await database.write { db in
                try PatientRecord.insert { PatientRecord(patient) }
                    .execute(db)
            }
            dismiss()
        } catch {
            saveErrorMessage = "The patient could not be saved."
        }
    }
}

private struct EditPatientForm: View {
    @Binding var draft: PatientDraft
    @Binding var saveErrorMessage: String?
    let guardedDismiss: FormSheetDismissAction
    let savePatient: @MainActor () async -> Void

    @State private var isPickingDOB = false
    @State private var draftDOB = Date()
    @State private var areOptionalDetailsExpanded = false

    init(
        draft: Binding<PatientDraft>,
        saveErrorMessage: Binding<String?>,
        guardedDismiss: FormSheetDismissAction,
        savePatient: @escaping @MainActor () async -> Void
    ) {
        self._draft = draft
        self._saveErrorMessage = saveErrorMessage
        self.guardedDismiss = guardedDismiss
        self.savePatient = savePatient
    }

    var body: some View {
        Form {
            Section {
                PhoneField("Phone number", phone: $draft.phone.replacingNil()) { contactName in
                    draft.prefillName(fromContactName: contactName)
                }
            }

            Section {
                TextField("Name", text: $draft.name.replacingNil())
                    .textContentType(.name)
                    .autocorrectionDisabled()
            }

            Section {
                DisclosureGroup("Optional details", isExpanded: $areOptionalDetailsExpanded) {
                    PatientDOBField(
                        title: "Date of birth",
                        selection: $draft.dob,
                        isPickingDOB: $isPickingDOB,
                        draftDOB: $draftDOB
                    )

                    PatientGenderField(title: "Gender", selection: $draft.gender)
                }
            }
            .fittedSheetContent()
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .navigationTitle("New Patient")
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
                AsyncButton("Done", systemImage: "checkmark") {
                    await savePatient()
                }
                .labelStyle(.iconOnly)
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
    EditPatientView()
}
