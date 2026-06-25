import Foundation
import SQLiteData

@MainActor @Observable class AppointmentBookingModel {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.calendar) var calendar
    @ObservationIgnored @FetchAll(ScheduleAppointmentRow.none) var appointmentRows

    var selectedDate: Date {
        didSet {
            draft.selectDate(selectedDate)
            prefillFirstAvailableSlotAfterLoadingAppointments()
        }
    }

    var draft: AppointmentBookingDraft
    var searchText = ""
    var isSaving = false
    var saveErrorMessage: String?
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
    }

    var appointments: [Appointment] {
        appointmentRows.compactMap(\.appointment)
    }

    func load() async throws {
        try await loadAppointments(for: selectedDate)
    }

    func loadAndPrefillFirstAvailableSlot() async {
        let searchDate = draft.selectedDate
        let durationMinutes = draft.durationMinutes
        let currentStart = draft.start
        try? await loadAppointments(for: searchDate)
        prefillFirstAvailableSlot(
            searchDate: searchDate,
            durationMinutes: durationMinutes,
            replacingStart: currentStart
        )
    }

    func selectDuration(_ durationMinutes: Int) {
        let selectedStart = draft.start
        draft.selectDuration(durationMinutes)
        prefillFirstAvailableSlotAfterLoadingAppointments(
            replacingStart: draft.start,
            preservingStartIfAvailable: selectedStart
        )
    }

    func saveAppointment() {
        let record: AppointmentRecord

        do {
            record = try draft.normalized.makeRecord(now: .now)
            // Reset error message
            saveErrorMessage = nil
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
            } catch {
                saveErrorMessage = "The appointment could not be saved."
            }
            isSaving = false
        }
    }

    private func loadAppointments(for selectedDate: Date) async throws {
        try await $appointmentRows.load(querySchedule(selectedDate: selectedDate))
    }

    private func prefillFirstAvailableSlotAfterLoadingAppointments() {
        let searchDate = draft.selectedDate
        let durationMinutes = draft.durationMinutes
        let currentStart = draft.start
        Task {
            try? await loadAppointments(for: searchDate)
            prefillFirstAvailableSlot(
                searchDate: searchDate,
                durationMinutes: durationMinutes,
                replacingStart: currentStart
            )
        }
    }

    private func prefillFirstAvailableSlotAfterLoadingAppointments(
        replacingStart expectedStart: Date,
        preservingStartIfAvailable startToPreserve: Date
    ) {
        let searchDate = draft.selectedDate
        let durationMinutes = draft.durationMinutes
        Task {
            try? await loadAppointments(for: searchDate)
            prefillFirstAvailableSlot(
                searchDate: searchDate,
                durationMinutes: durationMinutes,
                replacingStart: expectedStart,
                preservingStartIfAvailable: startToPreserve
            )
        }
    }

    private func prefillFirstAvailableSlot(
        searchDate: Date,
        durationMinutes: Int,
        replacingStart currentStart: Date?,
        preservingStartIfAvailable startToPreserve: Date? = nil
    ) {
        guard draft.selectedDate == searchDate,
            draft.durationMinutes == durationMinutes,
            currentStart == nil || draft.start == currentStart
        else {
            return
        }

        let availability = AppointmentAvailability(
            searchDate: searchDate,
            appointments: appointments,
            calendar: calendar
        )

        if let startToPreserve,
            availability.canFit(start: startToPreserve, durationMinutes: durationMinutes)
        {
            return
        }

        guard
            let slot = availability.firstAvailableSlot(
                neededDurationMinutes: durationMinutes
            )
        else {
            return
        }

        draft.start = slot
    }
}
