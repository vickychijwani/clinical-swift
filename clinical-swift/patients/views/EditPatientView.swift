import ClinicalModels
import Contacts
import SQLiteData
import SwiftUI

struct EditPatientView: View {
    @Environment(\.trayDismiss) private var dismiss
    @Environment(ToastStore.self) private var toast: ToastStore?

    @State private var model: PatientEditorModel
    @State private var dobRequest: DOBRequest?
    @State private var draftDOB = ClinicDate.today
    private let onSave: @MainActor (Patient) -> Void

    init(
        patient: Patient? = nil,
        initialDraft: PatientDraft = PatientDraft(),
        onSave: @escaping @MainActor (Patient) -> Void = { _ in }
    ) {
        _model = State(
            initialValue: PatientEditorModel(patient: patient, initialDraft: initialDraft)
        )
        self.onSave = onSave
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ConfirmingTray(
                // Reserve space for all optional fields so expansion does not move the tray.
                size: .height(370),
                hasUnsavedChanges: model.hasUnsavedChanges,
                title: "Discard unsaved changes?",
                message: "Your patient details have not been saved.",
                allowsInteractiveDismiss: !model.isSaving
            ) { guardedDismiss in
                EditPatientForm(
                    draft: $model.draft,
                    dobRequest: $dobRequest,
                    draftDOB: $draftDOB,
                    title: model.title,
                    guardedDismiss: guardedDismiss,
                    savePatient: savePatient
                )
            }
        }
        .disabled(model.isSaving)
        .background(AppColor.canvas)
        .trayStep(item: $dobRequest) { _ in
            PatientDOBPicker(dob: $model.draft.dob, draftDOB: $draftDOB)
        }
    }

    private func savePatient() async {
        if let patient = await model.save() {
            onSave(patient)
            dismiss()
        } else if let message = model.saveErrorMessage {
            toast?.show(message: message)
            model.dismissSaveError()
        }
    }
}

private struct EditPatientForm: View {
    @Binding var draft: PatientDraft
    @Binding var dobRequest: DOBRequest?
    @Binding var draftDOB: Date
    let title: String
    let guardedDismiss: TrayCancelAction
    let savePatient: @MainActor () async -> Void

    @State private var areOptionalDetailsExpanded = false
    @State private var hasRequestedContactsAccess = false

    init(
        draft: Binding<PatientDraft>,
        dobRequest: Binding<DOBRequest?>,
        draftDOB: Binding<Date>,
        title: String,
        guardedDismiss: TrayCancelAction,
        savePatient: @escaping @MainActor () async -> Void
    ) {
        self._draft = draft
        self._dobRequest = dobRequest
        self._draftDOB = draftDOB
        self.title = title
        self.guardedDismiss = guardedDismiss
        self.savePatient = savePatient
    }

    var body: some View {
        Form {
            Group {
                Section {
                    TextField("Name", text: $draft.name.replacingNil())
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section {
                    PhoneField("Phone number", phone: $draft.phone.replacingNil()) { contactName in
                        draft.prefillName(fromContactName: contactName)
                    } onContactPickerOpened: {
                        await requestContactsAccessIfNeeded()
                    }
                }

                Section {
                    DisclosureGroup("Optional details", isExpanded: $areOptionalDetailsExpanded) {
                        PatientDOBField(
                            title: "Date of birth",
                            selection: $draft.dob,
                            dobRequest: $dobRequest,
                            draftDOB: $draftDOB
                        )

                        PatientGenderField(title: "Gender", selection: $draft.gender)
                    }
                }
            }
            // The custom tray has no native sheet context to supply the subtle row fill.
            .listRowBackground(Rectangle().fill(.quinary))
        }
        .listSectionSpacing(.compact)
        .contentMargins(.vertical, 16, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .containerBackground(AppColor.canvas, for: .navigation)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                TrayCancelButton(action: guardedDismiss)
            }

            ToolbarItem(placement: .confirmationAction) {
                AsyncButton("Done", systemImage: "checkmark") {
                    await savePatient()
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    private func requestContactsAccessIfNeeded() async {
        guard !hasRequestedContactsAccess else { return }

        hasRequestedContactsAccess = true
        let contactStore = CNContactStore()
        _ = try? await contactStore.requestAccess(for: .contacts)
    }
}

private nonisolated struct DOBRequest: Identifiable, Sendable {
    let id = UUID()
}

private struct PatientDOBField: View {
    @Environment(\.clinicToday) private var clinicToday
    let title: String
    @Binding var selection: Date?
    @Binding var dobRequest: DOBRequest?
    @Binding var draftDOB: Date

    var body: some View {
        Button {
            draftDOB = selection.map(ClinicDate.day) ?? clinicToday
            dobRequest = DOBRequest()
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(AppColor.text)

                Spacer()

                Text(
                    selection?.formatted(ClinicDate.formatStyle.day().month().year()) ?? "Add"
                )
                .foregroundStyle(selection == nil ? AppColor.secondaryText : AppColor.text)
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
    @Environment(\.trayDismiss) private var dismiss
    @Environment(\.clinicToday) private var clinicToday

    var body: some View {
        NavigationStack {
            DatePicker(
                "Date of birth",
                selection: $draftDOB,
                in: ...clinicToday,
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
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dob = ClinicDate.day(draftDOB)
                        dismiss()
                    }
                }
            }
        }
        .trayOptions(size: .height(250))
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
