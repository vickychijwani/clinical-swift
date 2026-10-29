import ClinicalModels
import ClinicalPersistence
import Dependencies
import SQLiteData
import SwiftUI

struct ScheduleEditorSheet: View {
    @Environment(\.scenePhase) private var scenePhase
    @Dependency(\.date.now) private var now
    // Keep the loaded query when a type change rebuilds the sheet value.
    @State private var patientRows = FetchAll<PatientDetailsSelection>()
    @Bindable var session: ScheduleEditorSession
    @FocusState private var focusedField: ScheduleEditorSession.ItemType?
    @State private var patientCreationRequest: PatientCreationRequest?

    var body: some View {
        NavigationStack {
            VStack {
                if session.allowsTypeSelection {
                    Picker(
                        "Type",
                        selection: Binding(
                            get: { session.itemType }, set: { session.selectType($0) }
                        )
                    ) {
                        ForEach(ScheduleEditorSession.ItemType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding([.horizontal, .top])
                    .disabled(session.isWorking || patientCreationRequest != nil)
                }
                ScrollView {
                    switch session.editor {
                    case .appointment(let model):
                        AppointmentBookingPatientSelectionStep(
                            searchText: Binding(
                                get: { model.searchText }, set: { model.searchText = $0 }),
                            patientItems: filteredPatientItems(search: model.searchText),
                            searchIsFocused: $focusedField,
                            selectPatient: { session.selectPatient($0.patient) },
                            createPatient: {
                                focusedField = nil
                                patientCreationRequest = PatientCreationRequest(
                                    initialDraft: PatientDraft(name: model.searchText.nilIfBlank))
                            }
                        )
                        .padding()
                    case .unavailableTime(let model):
                        ScheduleEditorSection(title: "Label") {
                            TextField(
                                "Optional label",
                                text: Binding(
                                    get: { model.draft.label }, set: { model.draft.label = $0 })
                            )
                            .focused($focusedField, equals: .unavailableTime)
                            .submitLabel(.continue)
                            .onSubmit { session.isShowingSheet = false }
                        }
                        .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppColor.canvas)
            .navigationTitle(
                session.itemType == .appointment ? "Select Patient" : "Unavailable Time"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.left") { session.isShowingSheet = false }
                }
                if session.itemType == .unavailableTime {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Continue", systemImage: "checkmark") {
                            session.isShowingSheet = false
                        }
                    }
                }
            }
            .disabled(session.isWorking)
        }
        .presentationBackground(AppColor.canvas)
        .presentationBackgroundInteraction(.disabled)
        .task(id: session.itemType) {
            focusedField = nil
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedField = session.itemType
        }
        // Refresh when the app returns: an appointment may now be in the past.
        // Skip this when the app is inactive or patient selection is closed.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            // Refresh the time boundary on entry, then let database observation keep rows current.
            // Search text changes must not restart the query or change its time boundary.
            _ = try? await patientRows.load(appointmentBookingPatientRowsQuery(now: now))
        }
        .sheet(item: $patientCreationRequest, onDismiss: { focusedField = session.itemType }) {
            request in
            EditPatientView(initialDraft: request.initialDraft) { patient in
                session.selectPatient(patient)
            }
        }
    }

    private func filteredPatientItems(search: String) -> [PatientDetails] {
        let items = patientRows.wrappedValue.map(\.details)
        guard let query = search.nilIfBlank else { return items }
        return items.filter { PatientNameSearch.matches($0.patient.name, searchText: query) }
    }
}
private struct PatientCreationRequest: Identifiable {
    let id = UUID()
    let initialDraft: PatientDraft
}

private struct AppointmentBookingPatientSelectionStep: View {
    @Binding var searchText: String
    let patientItems: [PatientDetails]
    let searchIsFocused: FocusState<ScheduleEditorSession.ItemType?>.Binding
    let selectPatient: (PatientDetails) -> Void
    let createPatient: () -> Void

    var body: some View {
        ScheduleEditorSection(title: "Patient") {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColor.secondaryText)

                    TextField(
                        "Search patient by name",
                        text: $searchText
                    )
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused(searchIsFocused, equals: .appointment)

                    if !searchText.isEmpty {
                        Button("Clear", systemImage: "xmark.circle.fill") {
                            searchText = ""
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(AppColor.secondaryText)
                    }
                }
                .padding(10)
                .background(AppColor.surface)
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
                .background(AppColor.surface)
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
                    .foregroundStyle(AppColor.success)
                    .frame(width: 34, height: 34)
                    .background(AppColor.success.opacity(0.16))
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
