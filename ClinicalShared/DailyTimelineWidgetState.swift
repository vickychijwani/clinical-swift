import ClinicalModels
import Foundation

/// Persists the navigated day for the Daily Timeline widget in the shared App Group defaults.
/// Non-today selections expire after an idle timeout or at clinic midnight so stale days do not linger.
nonisolated struct DailyTimelineWidgetState: Sendable {
    struct Selection: Equatable, Sendable {
        let day: ScheduleDay
        let resetAt: Date?

        var isToday: Bool { resetAt == nil }
    }

    static let live = DailyTimelineWidgetState(
        suiteName: ClinicalSharedDatabase.appGroupIdentifier
    )
    static let idleResetInterval: TimeInterval = 15 * 60

    private static let selectedDayKey = "dailyTimeline.selectedDay"
    private static let expiresAtKey = "dailyTimeline.expiresAt"

    let suiteName: String

    init(suiteName: String) {
        self.suiteName = suiteName
    }

    func selection(
        at now: Date,
        calendar: Calendar = ClinicDate.calendar
    ) -> Selection {
        let today = ScheduleDay(date: now, calendar: calendar)
        guard
            let defaults = UserDefaults(suiteName: suiteName),
            let storedDayText = defaults.string(forKey: Self.selectedDayKey),
            let storedDay = ScheduleDay(storedDayText),
            storedDay != today
        else {
            return Selection(day: today, resetAt: nil)
        }

        let storedExpiry = defaults.double(forKey: Self.expiresAtKey)
        guard storedExpiry > 0 else {
            return Selection(day: today, resetAt: nil)
        }

        let expiresAt = Date(timeIntervalSinceReferenceDate: storedExpiry)
        guard expiresAt > now else {
            return Selection(day: today, resetAt: nil)
        }

        let nextMidnight = Self.nextMidnight(after: now, calendar: calendar)
        let resetAt = min(expiresAt, nextMidnight)
        guard resetAt > now else {
            return Selection(day: today, resetAt: nil)
        }

        return Selection(day: storedDay, resetAt: resetAt)
    }

    @discardableResult
    func step(
        byDays delta: Int,
        at now: Date,
        calendar: Calendar = ClinicDate.calendar
    ) -> ScheduleDay {
        let current = selection(at: now, calendar: calendar).day
        guard
            let currentDate = current.date(using: calendar),
            let targetDate = calendar.date(byAdding: .day, value: delta, to: currentDate)
        else {
            return current
        }

        let targetDay = ScheduleDay(date: targetDate, calendar: calendar)
        let today = ScheduleDay(date: now, calendar: calendar)
        if targetDay == today {
            resetToToday()
        } else if let defaults = UserDefaults(suiteName: suiteName) {
            let nextMidnight = Self.nextMidnight(after: now, calendar: calendar)
            let expiresAt = min(now.addingTimeInterval(Self.idleResetInterval), nextMidnight)
            defaults.set(targetDay.description, forKey: Self.selectedDayKey)
            defaults.set(expiresAt.timeIntervalSinceReferenceDate, forKey: Self.expiresAtKey)
        }
        return targetDay
    }

    func resetToToday() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removeObject(forKey: Self.selectedDayKey)
        defaults.removeObject(forKey: Self.expiresAtKey)
    }

    static func nextMidnight(
        after date: Date,
        calendar: Calendar = ClinicDate.calendar
    ) -> Date {
        calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? date.addingTimeInterval(60 * 60)
    }
}

/// Computes pre-generated WidgetKit entry timestamps for the Daily Timeline widget.
nonisolated enum DailyTimelineSchedule {
    static let nowMarkerIntervalMinutes = 10

    /// Returns entry dates covering `now` plus clinic-hour Now-marker ticks through closing,
    /// and a reload date at the next clinic midnight.
    static func todayEntryDates(
        from now: Date,
        intervalMinutes: Int = nowMarkerIntervalMinutes,
        calendar: Calendar = ClinicDate.calendar
    ) -> (entryDates: [Date], reloadDate: Date) {
        let today = calendar.startOfDay(for: now)
        let nextMidnight = DailyTimelineWidgetState.nextMidnight(after: now, calendar: calendar)
        let opening = Bitehaus.opening.on(date: today, using: calendar)
        let closing = Bitehaus.closing.on(date: today, using: calendar)

        var dates: [Date] = [now]
        guard intervalMinutes > 0, now < closing else {
            return (dates, nextMidnight)
        }

        var cursor = opening
        while cursor <= closing {
            if cursor > now {
                dates.append(cursor)
            }
            guard let next = calendar.date(byAdding: .minute, value: intervalMinutes, to: cursor)
            else { break }
            cursor = next
        }

        if let last = dates.last, last < closing {
            dates.append(closing)
        }

        return (dates, nextMidnight)
    }

    /// Returns entry dates for a browsed day followed by the full Today Now-marker schedule at `resetAt`.
    static func resetEntryDates(
        at now: Date,
        resetAt: Date,
        intervalMinutes: Int = nowMarkerIntervalMinutes,
        calendar: Calendar = ClinicDate.calendar
    ) -> (selectedDate: Date, resetEntryDates: [Date], reloadDate: Date) {
        let resetSchedule = todayEntryDates(
            from: resetAt,
            intervalMinutes: intervalMinutes,
            calendar: calendar
        )
        return (now, resetSchedule.entryDates, resetSchedule.reloadDate)
    }
}
