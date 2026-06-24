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
        draft.selectDuration(durationMinutes)
        prefillFirstAvailableSlotAfterLoadingAppointments()
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

    private func prefillFirstAvailableSlot(
        searchDate: Date,
        durationMinutes: Int,
        replacingStart currentStart: Date?
    ) {
        guard draft.selectedDate == searchDate,
              draft.durationMinutes == durationMinutes,
              currentStart == nil || draft.start == currentStart,
              let slot = firstAvailableSlot(
                searchDate: searchDate,
                neededDurationMinutes: durationMinutes
              ) else {
            return
        }

        draft.start = slot
    }

    private func firstAvailableSlot(
        searchDate: Date,
        neededDurationMinutes: Int
    ) -> Date? {
        var busyIntervals: [(start: Date, end: Date)] = appointments.map {
            ($0.start, $0.end)
        }
        busyIntervals.sort { $0.start < $1.start }

        let firstShiftSlot = firstAvailableSlot(
            from: Bitehaus.preferredFirstShiftStart.on(date: searchDate, using: calendar),
            to: Bitehaus.break.start.on(date: searchDate, using: calendar),
            neededDurationMinutes: neededDurationMinutes,
            busyIntervals: busyIntervals
        )
        if let firstShiftSlot {
            return firstShiftSlot
        }

        return firstAvailableSlot(
            from: Bitehaus.preferredSecondShiftStart.on(date: searchDate, using: calendar),
            to: Bitehaus.closing.on(date: searchDate, using: calendar),
            neededDurationMinutes: neededDurationMinutes,
            busyIntervals: busyIntervals
        )
    }

    private func firstAvailableSlot(
        from earliestAllowedStart: Date,
        to latestAllowedEnd: Date,
        neededDurationMinutes: Int,
        busyIntervals: [(start: Date, end: Date)]
    ) -> Date? {
        guard let latestAllowedStart = latestAllowedEnd.addMinutes(-neededDurationMinutes, using: calendar),
              earliestAllowedStart <= latestAllowedStart else {
            return nil
        }

        // Key Invariant: `candidate` is the earliest time that has not yet been ruled out
        var candidate = earliestAllowedStart

        for interval in busyIntervals {
            if candidate > latestAllowedStart {
                return nil
            }

            if interval.start >= latestAllowedEnd {
                break
            }

            // Ignore busy intervals that end before the candidate time
            if interval.end <= candidate {
                continue
            }

            guard let candidateEnd = candidate.addMinutes(neededDurationMinutes, using: calendar) else {
                return nil
            }

            // Gap found before the next busy interval
            if candidateEnd <= interval.start {
                return candidate
            }

            // Move candidate to the end of this busy interval
            candidate = max(candidate, interval.end)
        }

        // Check after the final busy interval
        return candidate <= latestAllowedStart ? candidate : nil
    }
}
