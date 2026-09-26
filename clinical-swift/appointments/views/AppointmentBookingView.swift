import Dependencies
import SQLiteData
import SwiftUI

struct AppointmentBookingView: View {
    @Environment(\.dismiss) private var dismiss

    @FetchAll(patientListRowsQuery())
    private var patientRows: [PatientDetailsSelection]

    @Bindable var model: AppointmentBookingModel

    @State private var bookingStep: AppointmentBookingStep

    /// Preserve the original draft as @State so unsaved changes can always be detected.
    /// This is not a simple property because it's initialized from the model; if the View is
    /// recreated it would end up overwriting the property with an edited draft.
    @State private var originalDraft: AppointmentBookingDraft

    init(model: AppointmentBookingModel) {
        self.model = model
        self._originalDraft = State(initialValue: model.draft.normalized)
        self._bookingStep = State(
            initialValue: model.draft.selectedPatient == nil ? .selectPatient : .details
        )
    }

    var body: some View {
        NavigationStack {
            ConfirmingFormSheet(
                hasUnsavedChanges: hasUnsavedChanges,
                title: "Discard unsaved appointment?",
                message: "Your appointment details have not been saved.",
                allowsInteractiveDismiss: false
            ) { guardedDismiss in
                AppointmentBookingForm(
                    model: model,
                    step: $bookingStep,
                    patientItems: patientRows.map(\.details),
                    guardedDismiss: guardedDismiss,
                    saveAppointment: saveAppointment
                )
            }
        }
        .modifier(FittedSheetModifier(fitsVertically: bookingStep == .details))
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color("AppBackground"))
        .presentationBackgroundInteraction(
            bookingStep == .details ? .enabled : .disabled
        )
    }

    private var hasUnsavedChanges: Bool {
        model.draft.normalized != originalDraft
    }

    private func saveAppointment() async {
        if await model.saveAppointment() {
            dismiss()
        }
    }
}

private enum AppointmentBookingStep: Equatable {
    case selectPatient
    case details
}

private struct AppointmentBookingForm: View {
    @Bindable var model: AppointmentBookingModel
    @Binding var step: AppointmentBookingStep

    @FocusState private var patientSearchIsFocused: Bool
    @State private var patientCreationRequest: PatientCreationRequest?

    let patientItems: [PatientDetails]
    let guardedDismiss: FormSheetDismissAction
    let saveAppointment: @MainActor () async -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color("AppBackground"))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == .details {
                        Button("Select Patient", systemImage: "chevron.left") {
                            selectPatientStep()
                        }
                    } else {
                        FormSheetCancelButton(action: guardedDismiss)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if step == .details {
                        AsyncButton("Done", systemImage: "checkmark") {
                            await saveAppointment()
                        }
                        .labelStyle(.iconOnly)
                    }
                }

                ToolbarItem(placement: .subtitle) {
                    if step == .details,
                        let patient = model.draft.selectedPatient
                    {
                        Text("For \(patient.displayName)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .task {
                patientSearchIsFocused = step == .selectPatient
            }
            .onChange(of: step) {
                patientSearchIsFocused = step == .selectPatient
            }
            .alert(
                "Unable to save appointment",
                isPresented: Binding(
                    get: { model.saveErrorMessage != nil },
                    set: { if !$0 { model.saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    model.saveErrorMessage = nil
                }
            } message: {
                Text(model.saveErrorMessage ?? "")
            }
            .sheet(item: $patientCreationRequest) { request in
                EditPatientView(initialDraft: request.initialDraft) { patient in
                    selectPatient(patient)
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .selectPatient:
            ScrollView {
                AppointmentBookingPatientSelectionStep(
                    searchText: $model.searchText,
                    patientItems: filteredPatientItems,
                    searchIsFocused: $patientSearchIsFocused,
                    selectPatient: selectPatient,
                    createPatient: createPatient
                )
                .padding()
            }

        case .details:
            VStack(alignment: .leading, spacing: 18) {
                AppointmentBookingTimeSection(start: startBinding)

                AppointmentBookingDurationSection(
                    durationMinutes: durationBinding
                )
            }
            .padding(.horizontal)
            .padding(.top, 2)
            .padding(.bottom)
            .fittedSheetContent()
        }
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { model.draft.start },
            set: { model.selectStart($0) }
        )
    }

    private var navigationTitle: String {
        switch step {
        case .selectPatient:
            "Select Patient"
        case .details:
            model.purpose.title
        }
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { model.draft.durationMinutes },
            set: { model.selectDuration($0) }
        )
    }

    private var filteredPatientItems: [PatientDetails] {
        guard let query = model.searchText.nilIfBlank else {
            return patientItems
        }

        return patientItems.filter { item in
            PatientNameSearch.matches(item.patient.name, searchText: query)
        }
    }

    private func selectPatient(_ patient: PatientDetails) {
        selectPatient(patient.patient)
    }

    private func selectPatient(_ patient: Patient) {
        model.draft.selectedPatient = patient
        model.searchText = ""
        step = .details
    }

    private func createPatient() {
        patientCreationRequest = PatientCreationRequest(
            initialDraft: PatientDraft(name: model.searchText.nilIfBlank)
        )
    }

    private func selectPatientStep() {
        step = .selectPatient
    }
}

private struct PatientCreationRequest: Identifiable {
    let id = UUID()
    let initialDraft: PatientDraft
}

private struct AppointmentBookingSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .styleSectionTitle()

            content
        }
    }
}

private struct AppointmentBookingPatientSelectionStep: View {
    @Binding var searchText: String
    let patientItems: [PatientDetails]
    let searchIsFocused: FocusState<Bool>.Binding
    let selectPatient: (PatientDetails) -> Void
    let createPatient: () -> Void

    var body: some View {
        AppointmentBookingSection(title: "Patient") {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(
                        "Search patient by name",
                        text: $searchText
                    )
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused(searchIsFocused)

                    if !searchText.isEmpty {
                        Button("Clear", systemImage: "xmark.circle.fill") {
                            searchText = ""
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.background)
                .clipShape(.capsule)

                LazyVStack(spacing: 0) {
                    ForEach(patientItems) { item in
                        AppointmentBookingPatientRow(item: item) {
                            selectPatient(item)
                        }

                        if item.id != patientItems.last?.id {
                            Divider()
                                .padding(.leading, 56)
                                .padding(.trailing, 24)
                        }
                    }

                    if let name = searchText.nilIfBlank {
                        if !patientItems.isEmpty {
                            Divider()
                                .padding(.leading, 56)
                                .padding(.trailing, 24)
                        }

                        AppointmentBookingCreatePatientRow(name: name, create: createPatient)
                    }
                }
                .background(.background)
                .clipShape(.rect(cornerRadius: 18))
            }
        }
    }
}

private struct AppointmentBookingPatientRow: View {
    let item: PatientDetails
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            PatientItemView(item: item)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct AppointmentBookingCreatePatientRow: View {
    let name: String
    let create: () -> Void

    var body: some View {
        Button(action: create) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.headline.pointSize(13))
                    .bold()
                    .foregroundStyle(.green)
                    .frame(width: 34, height: 34)
                    .background(.green.opacity(0.16))
                    .clipShape(.circle)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add new patient")
                        .styleBodyBold()

                    Text("Name: \(name)")
                        .styleCaption()
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct AppointmentBookingTimeSection: View {
    @Binding var start: Date

    var body: some View {
        AppointmentBookingSection(title: "Start Time") {
            DatePicker(
                "Start time",
                selection: $start,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
    }
}

private struct AppointmentBookingDurationSection: View {
    @Binding var durationMinutes: Minutes

    var body: some View {
        AppointmentBookingSection(title: "Duration") {
            Picker("Duration", selection: $durationMinutes) {
                ForEach(AppointmentBookingDraft.durationOptions, id: \.self) { minutes in
                    Text(durationLabel(for: minutes))
                        .tag(minutes)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func durationLabel(for minutes: Minutes) -> String {
        switch minutes {
        case 60:
            "1h"
        case 90:
            "1.5h"
        case 120:
            "2h"
        default:
            "\(minutes)m"
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    let model = AppointmentBookingModel(
        selectedDate: .now,
        selectedPatient: samplePatients.first(where: { $0.name != nil })!
    ) { _ in }

    AppointmentBookingView(model: model)
}
