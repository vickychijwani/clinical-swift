import Foundation
import SQLiteData

@MainActor @Observable class AppointmentBookingModel: Identifiable {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.calendar) var calendar
    @ObservationIgnored @Dependency(\.date.now) private var now

    /// This id lets the parent SwiftUI View (e.g., a sheet) identify whether the same or different
    /// item is being presented if the parent's item is re-assigned
    let id = UUID()
    let purpose: AppointmentBookingPurpose
    private let draftAppointmentID: Appointment.ID

    /// Prevent schedule reloads from moving an edited appointment just because its saved time
    /// overlaps another appointment or crosses a preferred scheduling boundary. Changing the date
    /// or duration enables normal automatic prefilling again.
    private var automaticallyPrefills: Bool

    var selectedDate: Date {
        didSet {
            draft.selectDate(selectedDate)
        }
    }

    var draft: AppointmentBookingDraft
    private(set) var appointments: [Appointment] = []
    var searchText = ""
    var saveErrorMessage: String?
    var draftPreviewScrollRequest = 0
    var onSaved: (Date) -> Void

    init(
        selectedDate: Date,
        selectedPatient: Patient? = nil,
        onSaved: @escaping (Date) -> Void
    ) {
        self.purpose = .create
        self.draftAppointmentID = UUID()
        self.automaticallyPrefills = true
        self.selectedDate = selectedDate
        self.draft = AppointmentBookingDraft(
            selectedPatient: selectedPatient,
            selectedDate: selectedDate
        )
        self.onSaved = onSaved
        self.selectedDate = draft.selectedDate
    }

    init(
        editing details: AppointmentDetails,
        onSaved: @escaping (Date) -> Void
    ) {
        let appointment = details.appointment
        self.purpose = .edit(appointment.id)
        self.draftAppointmentID = appointment.id
        self.automaticallyPrefills = false
        self.selectedDate = appointment.start
        self.draft = AppointmentBookingDraft(
            selectedPatient: details.patient,
            selectedDate: appointment.start,
            start: appointment.start,
            durationMinutes: appointment.durationMinutes
        )
        self.onSaved = onSaved
        self.selectedDate = draft.selectedDate
    }

    var draftAppointment: Appointment {
        Appointment(
            id: draftAppointmentID,
            patientName: draft.selectedPatient?.displayName ?? "<Select a patient>",
            start: draft.start,
            durationMinutes: draft.durationMinutes,
            status: .draft
        )
    }

    func selectDate(_ selectedDate: Date) {
        let normalizedDate = selectedDate.startOfDay(using: calendar)
        // If the selected date hasn't changed, do nothing.
        guard !normalizedDate.isSameDayAs(self.selectedDate) else {
            return
        }

        appointments = []
        automaticallyPrefills = true
        self.selectedDate = normalizedDate
    }

    func selectStart(_ start: Date) {
        let previousStart = draft.start
        draft.selectStart(start)
        requestDraftPreviewScrollIfNeeded(previousStart: previousStart)
    }

    func selectDuration(_ durationMinutes: Int) {
        let previousStart = draft.start
        draft.selectDuration(durationMinutes)
        automaticallyPrefills = true
        prefillFirstAvailableSlot(preservingStartIfAvailable: draft.start)
        requestDraftPreviewScrollIfNeeded(previousStart: previousStart)
    }

    func updateAppointments(_ appointments: [Appointment], for selectedDate: Date) {
        // Ignore a late async load after the user has already selected another day.
        guard selectedDate.isSameDayAs(self.selectedDate) else {
            return
        }

        let previousStart = draft.start

        // While editing, omit the persisted version of that appointment. Keeping both would
        // render duplicates and make availability suggestions treat it as its own conflict.
        self.appointments = appointments.filter { $0.id != purpose.editedAppointmentID }

        if !automaticallyPrefills {
            return
        }

        prefillFirstAvailableSlot(preservingStartIfAvailable: draft.start)
        requestDraftPreviewScrollIfNeeded(previousStart: previousStart)
    }

    func prefillFirstAvailableSlot() {
        let previousStart = draft.start
        prefillFirstAvailableSlot(preservingStartIfAvailable: nil)
        requestDraftPreviewScrollIfNeeded(previousStart: previousStart)
    }

    func saveAppointment() async -> Bool {
        do {
            try draft.normalized.validate()
            // Reset error message
            saveErrorMessage = nil
        } catch AppointmentBookingValidationError.missingPatient {
            saveErrorMessage = "Select a patient."
            return false
        } catch AppointmentBookingValidationError.invalidTime {
            saveErrorMessage = "Choose a time within clinic hours."
            return false
        } catch {
            saveErrorMessage = "Check the appointment details and try again."
            return false
        }

        do {
            // Keep the callback tied to the value being saved, even if the draft changes while the
            // database write suspends this method.
            let savedDate = draft.start
            switch purpose {
            case .create:
                let record = try draft.normalized.makeRecord(now: now)
                try await database.write { db in
                    try AppointmentRecord.insert { record }
                        .execute(db)
                }

            case .edit(let appointmentID):
                guard let patientID = draft.selectedPatient?.id else {
                    throw AppointmentBookingValidationError.missingPatient
                }
                // Pass one immutable snapshot into the database closure instead of accessing the
                // model's actor-isolated draft and clock from inside the write.
                let start = draft.start
                let durationMinutes = draft.durationMinutes
                let updatedAt = now

                try await database.write { db in
                    // Ensure the stored appointment status hasn't changed while editing
                    guard
                        let record = try AppointmentRecord.find(appointmentID).fetchOne(db),
                        record.status == Appointment.Status.scheduled.rawValue
                    else {
                        throw AppointmentEditingError.unavailable
                    }

                    try AppointmentRecord.find(appointmentID)
                        .update {
                            $0.patientID = patientID
                            $0.start = start
                            $0.durationMinutes = durationMinutes
                            $0.updatedAt = updatedAt
                        }
                        .execute(db)
                }
            }

            onSaved(savedDate)
            return true
        } catch {
            saveErrorMessage =
                if error is AppointmentEditingError {
                    "This appointment can no longer be edited."
                } else {
                    "The appointment could not be saved."
                }
            return false
        }
    }

    private var availability: AppointmentAvailability {
        AppointmentAvailability(
            searchDate: draft.selectedDate,
            appointments: appointments,
            calendar: calendar
        )
    }

    private func prefillFirstAvailableSlot(
        preservingStartIfAvailable startToPreserve: Date? = nil
    ) {
        if let startToPreserve,
            availability.canPrefill(
                start: startToPreserve,
                durationMinutes: draft.durationMinutes
            )
        {
            return
        }

        guard
            let slot = availability.firstAvailableSlot(
                neededDurationMinutes: draft.durationMinutes,
                earliestStart: earliestAutomaticPrefillStart
            )
        else {
            return
        }

        draft.start = slot
    }

    private var earliestAutomaticPrefillStart: Date? {
        guard calendar.isDate(draft.selectedDate, inSameDayAs: now) else {
            return nil
        }

        let boundaryMinutes = 5
        let currentMinutes = TimeOfDay(date: now, calendar: calendar).totalMinutes
        let roundedMinutes =
            ((currentMinutes + boundaryMinutes - 1) / boundaryMinutes) * boundaryMinutes

        return now.startOfDay(using: calendar).addMinutes(roundedMinutes, using: calendar)
    }

    /// This exists for reliably scrolling to preview the draft, if its slot has changed.
    /// A counter is useful here because it represents repeated events. The value doesn't have
    /// any domain meaning.
    private func requestDraftPreviewScrollIfNeeded(previousStart: Date) {
        if draft.start != previousStart {
            draftPreviewScrollRequest += 1
        }
    }
}

nonisolated enum AppointmentBookingPurpose: Equatable, Sendable {
    case create
    case edit(Appointment.ID)

    var title: String {
        switch self {
        case .create:
            "New Appointment"
        case .edit:
            "Edit Appointment"
        }
    }

    var editedAppointmentID: Appointment.ID? {
        guard case .edit(let id) = self else { return nil }
        return id
    }
}
