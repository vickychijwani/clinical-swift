import Dependencies
import SQLiteData
import SwiftUI

struct AppointmentBookingView: View {
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.defaultDatabase) private var database

    @FetchAll(patientListRowsQuery())
    private var patientRows: [PatientListRow]

    private let originalDraft: AppointmentBookingDraft
    private let onBooked: (Date) -> Void

    @State private var model: AppointmentBookingModel

    init(
        selectedPatient: PatientDetails? = nil,
        selectedDate: Date,
        onBooked: @escaping (Date) -> Void
    ) {
        let model = AppointmentBookingModel(
            selectedDate: selectedDate,
            selectedPatient: selectedPatient,
            onBooked: onBooked
        )
        self.onBooked = onBooked
        self.model = model
        self.originalDraft = model.draft.normalized
    }

    var body: some View {
        ConfirmingFormSheet(
            hasUnsavedChanges: hasUnsavedChanges,
            title: "Discard unsaved appointment?",
            message: "Your appointment details have not been saved.",
            primaryDetent: .large
        ) { guardedDismiss in
            AppointmentBookingForm(
                model: $model,
                patientItems: patientRows.map(\.item),
                guardedDismiss: guardedDismiss,
                saveAppointment: saveAppointment
            )
        }
    }

    private var hasUnsavedChanges: Bool {
        model.draft.normalized != originalDraft
    }

    private func saveAppointment() {
        model.saveAppointment()
        if model.saveErrorMessage == nil {
            dismiss()
        }
    }
}

private struct AppointmentBookingForm: View {
    @Dependency(\.calendar) private var calendar
    private let draftUuid = UUID()

    @Binding var model: AppointmentBookingModel

    let patientItems: [PatientDetails]
    let guardedDismiss: FormSheetDismissAction
    let saveAppointment: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AppointmentBookingPatientSection(
                    selectedPatient: $model.draft.selectedPatient,
                    searchText: $model.searchText,
                    patientItems: filteredPatientItems
                )

                AppointmentBookingDateSection(selectedDate: selectedDateBinding)

                AppointmentBookingTimeSection(start: $model.draft.start)

                AppointmentBookingDurationSection(
                    durationMinutes: durationBinding
                )

                timelinePreview
            }
            .padding()
        }
        .background(Color("AppBackground"))
        .navigationTitle("New Appointment")
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
                    saveAppointment()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                }
                .disabled(model.isSaving)
            }
        }
        .onChange(of: model.draft.start) { _, newValue in
            let normalized = model.draft.normalizedStart(
                newValue,
                selectedDate: model.draft.selectedDate,
                durationMinutes: model.draft.durationMinutes
            )
            if model.draft.start != normalized {
                model.draft.start = normalized
            }
        }
        .task {
            await model.loadAndPrefillFirstAvailableSlot()
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
    }

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { model.selectedDate },
            set: { model.selectedDate = $0 }
        )
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
            item.patient.name?.localizedStandardContains(query) == true
                || item.patient.phone?.localizedStandardContains(query) == true
        }
    }

    private var timelinePreview: some View {
        let time =
            $model.draft.start.wrappedValue.timeOfDay
            + $model.draft.durationMinutes.wrappedValue / 2
        return ClippedTimeline(at: time, height: 240) {
            Timeline(
                appointments: model.appointments + [
                    Appointment(
                        // Stable id for animations
                        id: draftUuid,
                        patientName: ($model.draft.selectedPatient).wrappedValue?.patient
                            .displayName ?? "<Select a patient>",
                        start: $model.draft.start.wrappedValue,
                        durationMinutes: durationBinding.wrappedValue,
                        status: .draft
                    )
                ],
                start: Bitehaus.opening,
                end: Bitehaus.closing,
                breakBlock: Bitehaus.break,
                showsNowMarker:
                    calendar
                    .isDateInToday(selectedDateBinding.wrappedValue)
            )
            .background(Color("AppBackground").opacity(0.3).blendMode(.screen))
        }
    }
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

private struct AppointmentBookingPatientSection: View {
    @Binding var selectedPatient: PatientDetails?
    @Binding var searchText: String
    let patientItems: [PatientDetails]

    var body: some View {
        AppointmentBookingSection(title: "Patient") {
            if let selectedPatient {
                HStack(spacing: 12) {
                    PatientItemView(item: selectedPatient)

                    Spacer()

                    Button {
                        self.selectedPatient = nil
                    } label: {
                        Label("Clear patient", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(.circle)
                }
                .padding(10)
                .background(.background)
                .clipShape(.rect(cornerRadius: 18))
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField(
                            "Search patient by name or phone",
                            text: $searchText
                        )
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

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
                    .clipShape(.rect(cornerRadius: 18))

                    LazyVStack(spacing: 0) {
                        ForEach(patientItems) { item in
                            AppointmentBookingPatientRow(item: item) {
                                selectedPatient = item
                                searchText = ""
                            }

                            if item.id != patientItems.last?.id {
                                Divider()
                                    .padding(.leading, 56)
                                    .padding(.trailing, 24)
                            }
                        }
                    }
                    .background(.background)
                    .clipShape(.rect(cornerRadius: 18))
                }
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

private struct AppointmentBookingDateSection: View {
    @Binding var selectedDate: Date

    var body: some View {
        AppointmentBookingSection(title: "Date") {
            WeekDateStrip(selectedDate: $selectedDate, displayMode: .sheet)
        }
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

    private let columns = [
        GridItem(.adaptive(minimum: 50), spacing: 8)
    ]

    var body: some View {
        AppointmentBookingSection(title: "Duration") {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AppointmentBookingDraft.durationOptions, id: \.self) { minutes in
                    Button {
                        durationMinutes = minutes
                    } label: {
                        Text(durationLabel(for: minutes))
                            .styleFormPicker()
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .buttonBorderShape(.capsule)
                    .tint(durationMinutes == minutes ? .accentColor : .secondary)
                }
            }
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
    NavigationStack {
        AppointmentBookingView(
            selectedPatient: PatientDetails(
                patient: samplePatients.first(where: { $0.name != nil })!,
                nextAppointmentDate: nil
            ),
            selectedDate: .now
        ) { _ in }
    }
}
