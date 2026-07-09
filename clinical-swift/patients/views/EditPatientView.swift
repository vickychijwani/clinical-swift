import SQLiteData
import SwiftUI

struct EditPatientView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: PatientEditorModel

    init(patient: Patient? = nil) {
        _model = State(initialValue: PatientEditorModel(patient: patient))
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ConfirmingFormSheet(
                hasUnsavedChanges: model.hasUnsavedChanges,
                title: "Discard unsaved changes?",
                message: "Your patient details have not been saved."
            ) { guardedDismiss in
                EditPatientForm(
                    draft: $model.draft,
                    title: model.title,
                    guardedDismiss: guardedDismiss,
                    savePatient: savePatient
                )
            }
        }
        .modifier(FittedSheetModifier(fitsVertically: true))
        .background(Color("AppBackground"))
        .alert(
            "Unable to save patient",
            isPresented: Binding(
                get: { model.saveErrorMessage != nil },
                set: { if !$0 { model.dismissSaveError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                model.dismissSaveError()
            }
        } message: {
            Text(model.saveErrorMessage ?? "")
        }
    }

    private func savePatient() async {
        if await model.save() {
            dismiss()
        }
    }
}

private struct EditPatientForm: View {
    @Binding var draft: PatientDraft
    let title: String
    let guardedDismiss: FormSheetDismissAction
    let savePatient: @MainActor () async -> Void

    @State private var isPickingDOB = false
    @State private var draftDOB = Date()
    @State private var areOptionalDetailsExpanded = false

    init(
        draft: Binding<PatientDraft>,
        title: String,
        guardedDismiss: FormSheetDismissAction,
        savePatient: @escaping @MainActor () async -> Void
    ) {
        self._draft = draft
        self.title = title
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                FormSheetCancelButton(action: guardedDismiss)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
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
