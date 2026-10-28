import ClinicalModels
import ClinicalPersistence
import Dependencies
import SQLiteData
import SwiftUI

struct AppointmentBookingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Dependency(\.date.now) private var now

    @FetchAll
    private var patientRows: [PatientDetailsSelection]

    @Bindable var model: AppointmentBookingModel

    var body: some View {
        NavigationStack {
            AppointmentBookingForm(model: model, patientItems: patientRows.map(\.details))
        }
        .interactiveDismissDisabled()
        .presentationDragIndicator(.hidden)
        .presentationBackground(AppColor.canvas)
        .presentationBackgroundInteraction(.disabled)
        // Refresh when the app returns: an appointment may now be in the past.
        // Skip this when the app is inactive or patient selection is closed.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            // Refresh the time boundary on entry, then let database observation keep rows current.
            // Search text changes must not restart the query or change its time boundary.
            _ = try? await $patientRows.load(appointmentBookingPatientRowsQuery(now: now))
        }
    }
}

private struct AppointmentBookingForm: View {
    @Bindable var model: AppointmentBookingModel

    @FocusState private var patientSearchIsFocused: Bool
    @State private var patientCreationRequest: PatientCreationRequest?

    let patientItems: [PatientDetails]

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColor.canvas)
        .navigationTitle("Select Patient")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") {
                    model.isSelectingPatient = false
                }
            }
        }
        .task {
            patientSearchIsFocused = true
        }
        .sheet(item: $patientCreationRequest) { request in
            EditPatientView(initialDraft: request.initialDraft) { patient in
                selectPatient(patient)
            }
        }
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
        model.selectPatient(patient)
    }

    private func createPatient() {
        patientCreationRequest = PatientCreationRequest(
            initialDraft: PatientDraft(name: model.searchText.nilIfBlank)
        )
    }
}

private struct PatientCreationRequest: Identifiable {
    let id = UUID()
    let initialDraft: PatientDraft
}

private struct AppointmentBookingPatientSelectionStep: View {
    @Binding var searchText: String
    let patientItems: [PatientDetails]
    let searchIsFocused: FocusState<Bool>.Binding
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
                    .focused(searchIsFocused)

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
