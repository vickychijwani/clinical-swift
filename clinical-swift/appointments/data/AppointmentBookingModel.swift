import Foundation
import SQLiteData

@MainActor @Observable class AppointmentBookingModel: Identifiable {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.calendar) var calendar

    /// This id lets the parent SwiftUI View (e.g., a sheet) identify whether the same or different
    /// item is being presented if the parent's item is re-assigned
    let id = UUID()
    private let draftAppointmentID = UUID()

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
    var onBooked: (Date) -> Void

    init(
        selectedDate: Date,
        selectedPatient: PatientDetails? = nil,
        onBooked: @escaping (Date) -> Void
    ) {
        self.selectedDate = selectedDate
        self.draft = AppointmentBookingDraft(
            selectedPatient: selectedPatient,
            selectedDate: selectedDate
        )
        self.onBooked = onBooked
        self.selectedDate = draft.selectedDate
    }

    var draftAppointment: Appointment {
        Appointment(
            id: draftAppointmentID,
            patientName: draft.selectedPatient?.patient.displayName ?? "<Select a patient>",
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
        prefillFirstAvailableSlot(preservingStartIfAvailable: draft.start)
        requestDraftPreviewScrollIfNeeded(previousStart: previousStart)
    }

    func updateAppointments(_ appointments: [Appointment], for selectedDate: Date) {
        // Ignore a late async load after the user has already selected another day.
        guard selectedDate.isSameDayAs(self.selectedDate) else {
            return
        }

        let previousStart = draft.start
        self.appointments = appointments
        prefillFirstAvailableSlot(preservingStartIfAvailable: draft.start)
        requestDraftPreviewScrollIfNeeded(previousStart: previousStart)
    }

    func prefillFirstAvailableSlot() {
        let previousStart = draft.start
        prefillFirstAvailableSlot(preservingStartIfAvailable: nil)
        requestDraftPreviewScrollIfNeeded(previousStart: previousStart)
    }

    func saveAppointment() async -> Bool {
        let record: AppointmentRecord

        do {
            record = try draft.normalized.makeRecord(now: .now)
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
            try await database.write { db in
                try AppointmentRecord.insert { record }
                    .execute(db)
            }
            onBooked(record.start)
            return true
        } catch {
            saveErrorMessage = "The appointment could not be saved."
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
                neededDurationMinutes: draft.durationMinutes
            )
        else {
            return
        }

        draft.start = slot
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
