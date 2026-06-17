import Dependencies
import SQLiteData
import SwiftUI

struct AppointmentBookingView: View {
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.defaultDatabase) private var database

    @FetchAll(patientListRowsQuery(), animation: .default)
    private var patientRows: [PatientListRow]

    private let originalDraft: AppointmentBookingDraft
    private let onBooked: (Date) -> Void

    @State private var draft: AppointmentBookingDraft
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(
        selectedDate: Date,
        onBooked: @escaping (Date) -> Void
    ) {
        let draft = AppointmentBookingDraft(selectedDate: selectedDate)
        self.originalDraft = draft.normalized
        self._draft = State(initialValue: draft)
        self.onBooked = onBooked
    }

    var body: some View {
        ConfirmingFormSheet(
            hasUnsavedChanges: hasUnsavedChanges,
            title: "Discard unsaved appointment?",
            message: "Your appointment details have not been saved.",
            primaryDetent: .large
        ) { guardedDismiss in
            AppointmentBookingForm(
                draft: $draft,
                searchText: $searchText,
                saveErrorMessage: $saveErrorMessage,
                isSaving: isSaving,
                patientItems: patientRows.map(\.item),
                guardedDismiss: guardedDismiss,
                saveAppointment: saveAppointment
            )
        }
    }

    private var hasUnsavedChanges: Bool {
        draft.normalized != originalDraft
    }

    private func saveAppointment() {
        let now = Date()
        let record: AppointmentRecord

        do {
            record = try draft.normalized.makeRecord(now: now)
        } catch AppointmentBookingValidationError.missingPatient {
            saveErrorMessage = "Select a patient."
            return
        } catch AppointmentBookingValidationError.invalidTime {
            saveErrorMessage = "Choose a time within clinic hours."
            return
        } catch {
            saveErrorMessage = "Check the appointment details and try again."
            return
        }

        isSaving = true
        Task {
            do {
                try await database.write { db in
                    try AppointmentRecord.insert { record }
                        .execute(db)
                }
                onBooked(draft.selectedDate)
                dismiss()
            } catch {
                saveErrorMessage = "The appointment could not be saved."
            }
            isSaving = false
        }
    }
}

private struct AppointmentBookingForm: View {
    @Binding var draft: AppointmentBookingDraft
    @Binding var searchText: String
    @Binding var saveErrorMessage: String?

    let isSaving: Bool
    let patientItems: [PatientListItem]
    let guardedDismiss: FormSheetDismissAction
    let saveAppointment: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AppointmentBookingPatientSection(
                    selectedPatient: $draft.selectedPatient,
                    searchText: $searchText,
                    patientItems: filteredPatientItems
                )

                AppointmentBookingDateSection(selectedDate: selectedDateBinding)

                AppointmentBookingTimeSection(startTime: $draft.startTime)

                AppointmentBookingDurationSection(
                    durationMinutes: durationBinding
                )
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
                .disabled(isSaving)
            }
        }
        .onChange(of: draft.startTime) { _, newValue in
            let normalized = draft.normalizedStartTime(
                newValue,
                selectedDate: draft.selectedDate,
                durationMinutes: draft.durationMinutes
            )
            if draft.startTime != normalized {
                draft.startTime = normalized
            }
        }
        .alert(
            "Unable to save appointment",
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

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { draft.selectedDate },
            set: { draft.selectDate($0) }
        )
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { draft.durationMinutes },
            set: { draft.selectDuration($0) }
        )
    }

    private var filteredPatientItems: [PatientListItem] {
        guard let query = searchText.nilIfBlank else {
            return patientItems
        }

        return patientItems.filter { item in
            item.patient.name?.localizedStandardContains(query) == true
                || item.patient.phone?.localizedStandardContains(query) == true
        }
    }
}

private struct AppointmentBookingSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content
        }
    }
}

private struct AppointmentBookingPatientSection: View {
    @Binding var selectedPatient: PatientListItem?
    @Binding var searchText: String
    let patientItems: [PatientListItem]

    var body: some View {
        AppointmentBookingSection(title: "Patient") {
            if let selectedPatient {
                HStack(spacing: 12) {
                    PatientRow(item: selectedPatient)

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
                .padding()
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
                    .padding()
                    .background(.background)
                    .clipShape(.rect(cornerRadius: 18))

                    LazyVStack(spacing: 0) {
                        ForEach(patientItems) { item in
                            Button {
                                selectedPatient = item
                                searchText = ""
                            } label: {
                                PatientRow(item: item)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                            .buttonStyle(.plain)

                            if item.id != patientItems.last?.id {
                                Divider()
                                    .padding(.leading, 62)
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

private struct AppointmentBookingDateSection: View {
    @Binding var selectedDate: Date

    var body: some View {
        AppointmentBookingSection(title: "Date") {
            WeekDateStrip(selectedDate: $selectedDate, displayMode: .sheet)
        }
    }
}

private struct AppointmentBookingTimeSection: View {
    @Binding var startTime: Date

    var body: some View {
        AppointmentBookingSection(title: "Start Time") {
            DatePicker(
                "Start time",
                selection: $startTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
        }
    }
}

private struct AppointmentBookingDurationSection: View {
    @Binding var durationMinutes: Int

    private let columns = [
        GridItem(.adaptive(minimum: 88), spacing: 10)
    ]

    var body: some View {
        AppointmentBookingSection(title: "Duration") {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AppointmentBookingDraft.durationOptions, id: \.self) { minutes in
                    Button {
                        durationMinutes = minutes
                    } label: {
                        Text(durationLabel(for: minutes))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .tint(durationMinutes == minutes ? .accentColor : .secondary)
                }
            }
        }
    }

    private func durationLabel(for minutes: Int) -> String {
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
        AppointmentBookingView(selectedDate: .now) { _ in }
    }
}
