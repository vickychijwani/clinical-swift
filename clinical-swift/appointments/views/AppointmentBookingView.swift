import Dependencies
import SQLiteData
import SwiftUI

enum AppointmentBookingSheetMetrics {
    static let fallbackCompactDetentHeight: CGFloat = 320
    static let minimumCompactDetentHeight: CGFloat = 220
    static let nativeNavigationHeaderHeight: CGFloat = 64
}

struct AppointmentBookingView: View {
    @Environment(\.dismiss) private var dismiss

    @FetchAll(patientListRowsQuery())
    private var patientRows: [PatientListRow]

    @Bindable var model: AppointmentBookingModel
    @Binding var compactSheetHeight: CGFloat

    @State private var bookingStep: AppointmentBookingStep

    /// Preserve the original draft as @State so unsaved changes can always be detected.
    /// This is not a simple property because it's initialized from the model; if the View is
    /// recreated it would end up overwriting the property with an edited draft.
    @State private var originalDraft: AppointmentBookingDraft

    init(model: AppointmentBookingModel, compactSheetHeight: Binding<CGFloat>) {
        self.model = model
        self._compactSheetHeight = compactSheetHeight
        self._originalDraft = State(initialValue: model.draft.normalized)
        self._bookingStep = State(
            initialValue: model.draft.selectedPatient == nil ? .selectPatient : .details
        )
    }

    var body: some View {
        ConfirmingFormSheet(
            hasUnsavedChanges: hasUnsavedChanges,
            title: "Discard unsaved appointment?",
            message: "Your appointment details have not been saved.",
            primaryDetent: bookingStep.presentationDetent(compactHeight: compactSheetHeight),
            allowsInteractiveDismiss: false
        ) { guardedDismiss in
            AppointmentBookingForm(
                model: model,
                step: $bookingStep,
                compactSheetHeight: $compactSheetHeight,
                patientItems: patientRows.map(\.item),
                guardedDismiss: guardedDismiss,
                saveAppointment: saveAppointment
            )
        }
        .presentationBackground(Color("AppBackground"))
        .presentationBackgroundInteraction(.enabled)
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

    var title: String {
        switch self {
        case .selectPatient:
            "Select Patient"
        case .details:
            "New Appointment"
        }
    }

    func presentationDetent(compactHeight: CGFloat) -> PresentationDetent {
        switch self {
        case .selectPatient:
            .large
        case .details:
            .height(compactHeight)
        }
    }
}

private struct AppointmentBookingForm: View {
    @Bindable var model: AppointmentBookingModel
    @Binding var step: AppointmentBookingStep
    @Binding var compactSheetHeight: CGFloat

    @FocusState private var patientSearchIsFocused: Bool

    let patientItems: [PatientDetails]
    let guardedDismiss: FormSheetDismissAction
    let saveAppointment: @MainActor () async -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .top)
            .background(Color("AppBackground"))
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == .details {
                        Button("Select Patient", systemImage: "chevron.left") {
                            selectPatientStep()
                        }
                    } else {
                        Button {
                            guardedDismiss()
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                                .labelStyle(.iconOnly)
                        }
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
                        Text("For \(patient.patient.displayName)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height.rounded(.up)
            } action: { newHeight in
                updateCompactSheetHeight(newHeight)
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
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .selectPatient:
            ScrollView {
                AppointmentBookingPatientSelectionStep(
                    searchText: $model.searchText,
                    patientItems: filteredPatientItems,
                    searchIsFocused: $patientSearchIsFocused,
                    selectPatient: selectPatient
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
        }
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { model.draft.start },
            set: { model.selectStart($0) }
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
            PatientNameSearch.matches(item.patient.name, searchText: query)
        }
    }

    private func selectPatient(_ patient: PatientDetails) {
        model.draft.selectedPatient = patient
        model.searchText = ""
        step = .details
    }

    private func selectPatientStep() {
        step = .selectPatient
        patientSearchIsFocused = true
    }

    private func updateCompactSheetHeight(_ measuredHeight: CGFloat) {
        guard step == .details else {
            return
        }

        let height = max(
            measuredHeight + AppointmentBookingSheetMetrics.nativeNavigationHeaderHeight,
            AppointmentBookingSheetMetrics.minimumCompactDetentHeight
        )

        guard abs(height - compactSheetHeight) > 0.5 else {
            return
        }

        compactSheetHeight = height
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

private struct AppointmentBookingPatientSelectionStep: View {
    @Binding var searchText: String
    let patientItems: [PatientDetails]
    let searchIsFocused: FocusState<Bool>.Binding
    let selectPatient: (PatientDetails) -> Void

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
                .clipShape(.rect(cornerRadius: 18))

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
    @Previewable @State var compactSheetHeight =
        AppointmentBookingSheetMetrics.fallbackCompactDetentHeight

    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    let model = AppointmentBookingModel(
        selectedDate: .now,
        selectedPatient: PatientDetails(
            patient: samplePatients.first(where: { $0.name != nil })!,
            nextAppointmentDate: nil
        )
    ) { _ in }

    NavigationStack {
        AppointmentBookingView(
            model: model,
            compactSheetHeight: $compactSheetHeight
        )
    }
}
