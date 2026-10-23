import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation

struct AppointmentBookingDraft: Equatable, Sendable {
    static let durationOptions = ScheduleDurationSection.options

    @Dependency(\.calendar) private var calendar

    var selectedPatient: Patient?
    var selectedDate: Date
    var start: Date
    var durationMinutes: Int

    init(
        selectedPatient: Patient? = nil,
        selectedDate: Date,
        start: Date? = nil,
        durationMinutes: Int = 30
    ) {
        self.selectedPatient = selectedPatient
        self.selectedDate = selectedDate
        self.start = start ?? selectedDate
        self.durationMinutes = durationMinutes

        let normalizedDate = selectedDate.startOfDay(using: calendar)
        self.selectedDate = normalizedDate
        self.start = normalizedStart(
            start ?? Bitehaus.opening.on(date: normalizedDate, using: calendar),
            selectedDate: normalizedDate,
            durationMinutes: durationMinutes
        )
    }

    static func == (lhs: AppointmentBookingDraft, rhs: AppointmentBookingDraft) -> Bool {
        lhs.selectedPatient == rhs.selectedPatient
            && lhs.selectedDate == rhs.selectedDate
            && lhs.start == rhs.start
            && lhs.durationMinutes == rhs.durationMinutes
    }

    var normalized: AppointmentBookingDraft {
        AppointmentBookingDraft(
            selectedPatient: selectedPatient,
            selectedDate: selectedDate,
            start: start,
            durationMinutes: durationMinutes
        )
    }

    mutating func selectDate(_ date: Date) {
        selectedDate = date.startOfDay(using: calendar)
        start = normalizedStart(
            start,
            selectedDate: selectedDate,
            durationMinutes: durationMinutes
        )
    }

    mutating func selectStart(_ date: Date) {
        start = normalizedStart(
            date,
            selectedDate: selectedDate,
            durationMinutes: durationMinutes
        )
    }

    mutating func selectDuration(_ durationMinutes: Int) {
        self.durationMinutes = durationMinutes
        start = normalizedStart(
            start,
            selectedDate: selectedDate,
            durationMinutes: durationMinutes
        )
    }

    func validate() throws {
        guard selectedPatient != nil else {
            throw AppointmentBookingValidationError.missingPatient
        }

        let opening = Bitehaus.opening.on(date: selectedDate, using: calendar)
        let closing = Bitehaus.closing.on(date: selectedDate, using: calendar)
        guard start >= opening,
            let end = calendar.date(
                byAdding: .minute,
                value: durationMinutes,
                to: start
            ),
            end <= closing
        else {
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

        return try AppointmentRecord.persisted(
            id: id,
            patientID: selectedPatient.id,
            start: start,
            durationMinutes: durationMinutes,
            status: .scheduled,
            createdAt: now,
            updatedAt: now
        )
    }

    func normalizedStart(
        _ proposedTime: Date,
        selectedDate: Date,
        durationMinutes: Int
    ) -> Date {
        let proposedMinutes = TimeOfDay(date: proposedTime, calendar: calendar).totalMinutes
        let openingMinutes = Bitehaus.opening.totalMinutes
        let maxStartMinutes = Bitehaus.closing.totalMinutes - durationMinutes
        let clampedMinutes =
            if maxStartMinutes >= openingMinutes {
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
