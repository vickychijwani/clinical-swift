import ClinicalModels
import Foundation

nonisolated struct AppointmentAvailability {
    private let searchDate: Date
    private let appointments: [Appointment]
    private let calendar: Calendar

    init(
        searchDate: Date,
        appointments: [Appointment],
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.searchDate = searchDate
        self.appointments = appointments
        self.calendar = calendar
    }

    func canPrefill(start: Date, durationMinutes: Int) -> Bool {
        guard let end = start.addMinutes(durationMinutes, using: calendar),
            fitsWithinWorkingSegment(start: start, end: end)
        else {
            return false
        }

        return !busyIntervals.contains { interval in
            start < interval.end && end > interval.start
        }
    }

    func firstAvailableSlot(
        neededDurationMinutes: Int,
        earliestStart: Date? = nil
    ) -> Date? {
        let windows = searchWindows(earliestStart: earliestStart)

        for window in windows {
            if let slot = firstAvailableSlot(
                from: window.start,
                to: window.end,
                neededDurationMinutes: neededDurationMinutes
            ) {
                return slot
            }
        }

        return nil
    }

    private var busyIntervals: [(start: Date, end: Date)] {
        appointments
            .compactMap { appointment -> (start: Date, end: Date)? in
                guard
                    let end = appointment.start.addMinutes(
                        appointment.durationMinutes,
                        using: calendar
                    )
                else {
                    return nil
                }

                return (appointment.start, end)
            }
            .sorted { $0.start < $1.start }
    }

    private func fitsWithinWorkingSegment(start: Date, end: Date) -> Bool {
        let firstShiftStart = Bitehaus.opening.on(date: searchDate, using: calendar)
        let firstShiftEnd = Bitehaus.break.start.on(date: searchDate, using: calendar)
        let secondShiftStart = Bitehaus.break.end.on(date: searchDate, using: calendar)
        let secondShiftEnd = Bitehaus.closing.on(date: searchDate, using: calendar)

        return (start >= firstShiftStart && end <= firstShiftEnd)
            || (start >= secondShiftStart && end <= secondShiftEnd)
    }

    private func firstAvailableSlot(
        from earliestAllowedStart: Date,
        to latestAllowedEnd: Date,
        neededDurationMinutes: Int
    ) -> Date? {
        guard
            let latestAllowedStart = latestAllowedEnd.addMinutes(
                -neededDurationMinutes,
                using: calendar
            ),
            earliestAllowedStart <= latestAllowedStart
        else {
            return nil
        }

        var candidate = earliestAllowedStart

        for interval in busyIntervals {
            if candidate > latestAllowedStart {
                return nil
            }

            if interval.start >= latestAllowedEnd {
                break
            }

            if interval.end <= candidate {
                continue
            }

            guard let candidateEnd = candidate.addMinutes(neededDurationMinutes, using: calendar)
            else {
                return nil
            }

            if candidateEnd <= interval.start {
                return candidate
            }

            candidate = max(candidate, interval.end)
        }

        return candidate <= latestAllowedStart ? candidate : nil
    }

    private func searchWindows(earliestStart: Date?) -> [(start: Date, end: Date)] {
        if let earliestStart {
            return [
                (
                    max(earliestStart, Bitehaus.opening.on(date: searchDate, using: calendar)),
                    Bitehaus.break.start.on(date: searchDate, using: calendar)
                ),
                (
                    max(earliestStart, Bitehaus.break.end.on(date: searchDate, using: calendar)),
                    Bitehaus.closing.on(date: searchDate, using: calendar)
                ),
            ]
        }

        return [
            (
                Bitehaus.preferredFirstShiftStart.on(date: searchDate, using: calendar),
                Bitehaus.break.start.on(date: searchDate, using: calendar)
            ),
            (
                Bitehaus.preferredSecondShiftStart.on(date: searchDate, using: calendar),
                Bitehaus.closing.on(date: searchDate, using: calendar)
            ),
        ]
    }
}
