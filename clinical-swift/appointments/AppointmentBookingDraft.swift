import Dependencies
import Foundation

nonisolated struct AppointmentBookingDraft: Equatable, Sendable {
    static let durationOptions = [15, 30, 45, 60, 90, 120]

    @Dependency(\.calendar) private var calendar

    var selectedPatient: PatientListItem?
    var selectedDate: Date
    var startTime: Date
    var durationMinutes: Int

    init(
        selectedPatient: PatientListItem? = nil,
        selectedDate: Date,
        startTime: Date? = nil,
        durationMinutes: Int = 30
    ) {
        self.selectedPatient = selectedPatient
        self.selectedDate = selectedDate
        self.startTime = startTime ?? selectedDate
        self.durationMinutes = durationMinutes

        let normalizedDate = selectedDate.startOfDay(using: calendar)
        self.selectedDate = normalizedDate
        self.startTime = normalizedStartTime(
            startTime ?? Bitehaus.startTime.on(date: normalizedDate, using: calendar),
            selectedDate: normalizedDate,
            durationMinutes: durationMinutes
        )
    }

    static func == (lhs: AppointmentBookingDraft, rhs: AppointmentBookingDraft) -> Bool {
        lhs.selectedPatient == rhs.selectedPatient
            && lhs.selectedDate == rhs.selectedDate
            && lhs.startTime == rhs.startTime
            && lhs.durationMinutes == rhs.durationMinutes
    }

    var normalized: AppointmentBookingDraft {
        AppointmentBookingDraft(
            selectedPatient: selectedPatient,
            selectedDate: selectedDate,
            startTime: startTime,
            durationMinutes: durationMinutes
        )
    }

    mutating func selectDate(_ date: Date) {
        selectedDate = date.startOfDay(using: calendar)
        startTime = normalizedStartTime(
            startTime,
            selectedDate: selectedDate,
            durationMinutes: durationMinutes
        )
    }

    mutating func selectStartTime(_ date: Date) {
        startTime = normalizedStartTime(
            date,
            selectedDate: selectedDate,
            durationMinutes: durationMinutes
        )
    }

    mutating func selectDuration(_ durationMinutes: Int) {
        self.durationMinutes = durationMinutes
        startTime = normalizedStartTime(
            startTime,
            selectedDate: selectedDate,
            durationMinutes: durationMinutes
        )
    }

    func validate() throws {
        guard selectedPatient != nil else {
            throw AppointmentBookingValidationError.missingPatient
        }

        let opening = Bitehaus.startTime.on(date: selectedDate, using: calendar)
        let closing = Bitehaus.closingTime.on(date: selectedDate, using: calendar)
        guard startTime >= opening,
              let endTime = calendar.date(
                byAdding: .minute,
                value: durationMinutes,
                to: startTime
              ),
              endTime <= closing else {
            throw AppointmentBookingValidationError.invalidTime
        }
    }

    func makeRecord(
        id: UUID = UUID(),
        now: Date = .now
    ) throws -> AppointmentRecord {
        try validate()
        guard let selectedPatient else {
            throw AppointmentBookingValidationError.missingPatient
        }

        return AppointmentRecord(
            id: id,
            patientID: selectedPatient.patient.id,
            startTime: startTime,
            durationMinutes: durationMinutes,
            status: Appointment.Status.scheduled.storageValue,
            createdAt: now,
            updatedAt: now
        )
    }

    func normalizedStartTime(
        _ proposedTime: Date,
        selectedDate: Date,
        durationMinutes: Int
    ) -> Date {
        let proposedMinutes = TimeOfDay(date: proposedTime, calendar: calendar).totalMinutes
        let openingMinutes = Bitehaus.startTime.totalMinutes
        let maxStartMinutes = Bitehaus.closingTime.totalMinutes - durationMinutes
        let clampedMinutes = if maxStartMinutes >= openingMinutes {
            min(max(proposedMinutes, openingMinutes), maxStartMinutes)
        } else {
            openingMinutes
        }

        return TimeOfDay(
            clampedMinutes / 60,
            clampedMinutes % 60
        )
        .on(date: selectedDate.startOfDay(using: calendar), using: calendar)
    }
}

nonisolated enum AppointmentBookingValidationError: Error, Equatable {
    case missingPatient
    case invalidTime
}
