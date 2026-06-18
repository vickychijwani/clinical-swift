import Dependencies
import Foundation

struct AppointmentBookingDraft: Equatable, Sendable {
    static let durationOptions = [15, 30, 45, 60, 90, 120]

    @Dependency(\.calendar) private var calendar

    var selectedPatient: PatientDetails?
    var selectedDate: Date
    var startTime: Date
    var durationMinutes: Int

    init(
        selectedPatient: PatientDetails? = nil,
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
            selectedDate: normalizedDate
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

    var startTimeOfDay: TimeOfDay {
        TimeOfDay(date: startTime, calendar: calendar)
    }

    mutating func selectDate(_ date: Date) {
        selectedDate = date.startOfDay(using: calendar)
        startTime = normalizedStartTime(
            startTime,
            selectedDate: selectedDate
        )
    }

    mutating func selectStartTime(_ time: TimeOfDay) {
        startTime = normalizedStartTime(
            time.on(date: selectedDate, using: calendar),
            selectedDate: selectedDate
        )
    }

    mutating func selectDuration(_ durationMinutes: Int) {
        self.durationMinutes = durationMinutes
    }

    func validate() throws {
        guard selectedPatient != nil else {
            throw AppointmentBookingValidationError.missingPatient
        }

        let opening = Bitehaus.startTime.on(date: selectedDate, using: calendar)
        let latestStart = Bitehaus.latestAppointmentStartTime.on(
            date: selectedDate,
            using: calendar
        )
        guard startTime >= opening,
              startTime <= latestStart,
              durationMinutes > 0 else {
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
        selectedDate: Date
    ) -> Date {
        let proposedMinutes = TimeOfDay(date: proposedTime, calendar: calendar).totalMinutes
        let openingMinutes = Bitehaus.startTime.totalMinutes
        let latestStartMinutes = Bitehaus.latestAppointmentStartTime.totalMinutes
        let clampedMinutes = min(
            max(proposedMinutes, openingMinutes),
            latestStartMinutes
        )

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
