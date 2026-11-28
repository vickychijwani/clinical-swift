import ClinicalModels
import Foundation
import Synchronization

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
    private static let fastTodayPendingKey = "dailyTimeline.fastTodayPending"
    // Serialize concurrent widget intent read-modify-write calls so rapid taps cannot drop a step.
    private static let lock = Mutex<Void>(())

    let suiteName: String

    init(suiteName: String) {
        self.suiteName = suiteName
    }

    func selection(
        at now: Date,
        calendar: Calendar = ClinicDate.calendar
    ) -> Selection {
        Self.lock.withLock { _ in
            unlockedSelection(at: now, calendar: calendar)
        }
    }

    @discardableResult
    func step(
        byDays delta: Int,
        at now: Date,
        calendar: Calendar = ClinicDate.calendar
    ) -> ScheduleDay {
        Self.lock.withLock { _ in
            let current = unlockedSelection(at: now, calendar: calendar).day
            guard
                let currentDate = current.date(using: calendar),
                let targetDate = calendar.date(byAdding: .day, value: delta, to: currentDate)
            else {
                return current
            }

            let targetDay = ScheduleDay(date: targetDate, calendar: calendar)
            let today = ScheduleDay(date: now, calendar: calendar)
            if targetDay == today {
                unlockedResetToToday(markFastReturn: true)
            } else if let defaults = UserDefaults(suiteName: suiteName) {
                let nextMidnight = Self.nextMidnight(after: now, calendar: calendar)
                let expiresAt = min(now.addingTimeInterval(Self.idleResetInterval), nextMidnight)
                defaults.set(targetDay.description, forKey: Self.selectedDayKey)
                defaults.set(expiresAt.timeIntervalSinceReferenceDate, forKey: Self.expiresAtKey)
                defaults.removeObject(forKey: Self.fastTodayPendingKey)
            }
            return targetDay
        }
    }

    func resetToToday(markFastReturn: Bool = true) {
        Self.lock.withLock { _ in
            unlockedResetToToday(markFastReturn: markFastReturn)
        }
    }

    /// Consumes the one-shot fast-return flag set by interactive taps landing on Today so
    /// the tap archives at most 2 entries and lets the next background reload build the full window.
    func consumeFastTodayPending() -> Bool {
        Self.lock.withLock { _ in
            guard let defaults = UserDefaults(suiteName: suiteName) else { return false }
            let pending = defaults.bool(forKey: Self.fastTodayPendingKey)
            if pending {
                defaults.removeObject(forKey: Self.fastTodayPendingKey)
            }
            return pending
        }
    }

    private func unlockedResetToToday(markFastReturn: Bool) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removeObject(forKey: Self.selectedDayKey)
        defaults.removeObject(forKey: Self.expiresAtKey)
        if markFastReturn {
            defaults.set(true, forKey: Self.fastTodayPendingKey)
        } else {
            defaults.removeObject(forKey: Self.fastTodayPendingKey)
        }
    }

    private func unlockedSelection(
        at now: Date,
        calendar: Calendar
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

    #if DEBUG
        private static let debugTimeOfDayMinutesKey = "dailyTimeline.debugTimeOfDayMinutes"

        /// Overrides the clinic time-of-day (minutes since clinic midnight) in DEBUG builds so
        /// morning-hour widget timelines are tested consistently at any wall-clock time.
        func setDebugTimeOfDayMinutes(_ minutes: Int?) {
            guard let defaults = UserDefaults(suiteName: suiteName) else { return }
            if let minutes {
                defaults.set(minutes, forKey: Self.debugTimeOfDayMinutesKey)
            } else {
                defaults.removeObject(forKey: Self.debugTimeOfDayMinutesKey)
            }
        }

        func effectiveNow(from realNow: Date, calendar: Calendar = ClinicDate.calendar) -> Date {
            guard
                let defaults = UserDefaults(suiteName: suiteName),
                let minutes = defaults.object(forKey: Self.debugTimeOfDayMinutesKey) as? Int
            else {
                return realNow
            }
            let dayStart = calendar.startOfDay(for: realNow)
            return calendar.date(byAdding: .minute, value: minutes, to: dayStart) ?? realNow
        }
    #endif

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
    static let nowMarkerWindowMinutes = 90

    /// Returns entry dates for a short rolling Now-marker window on today, and the next reload date.
    /// Keeping the window short avoids archiving a full day of widget views on every tap while
    /// staying well within WidgetKit's daily background reload budget.
    static func todayEntryDates(
        from now: Date,
        intervalMinutes: Int = nowMarkerIntervalMinutes,
        windowMinutes: Int = nowMarkerWindowMinutes,
        preferFastReturn: Bool = false,
        calendar: Calendar = ClinicDate.calendar
    ) -> (entryDates: [Date], reloadDate: Date) {
        let today = calendar.startOfDay(for: now)
        let nextMidnight = DailyTimelineWidgetState.nextMidnight(after: now, calendar: calendar)
        let opening = Bitehaus.opening.on(date: today, using: calendar)
        let closing = Bitehaus.closing.on(date: today, using: calendar)

        guard intervalMinutes > 0, windowMinutes > 0, now < closing else {
            return ([now], nextMidnight)
        }

        if now < opening {
            if preferFastReturn {
                return ([now], opening)
            }
            // Avoid pre-opening reloads; include opening so the Now marker appears even if reload lags.
            return ([now, opening], opening)
        }

        if preferFastReturn {
            // On an interactive tap back to Today, emit only 1 entry ([now]) so taps stay as fast
            // as possible, then reload at nextTick (including closing so the Now marker clears on time).
            var cursor = opening
            while cursor <= now {
                guard
                    let next = calendar.date(byAdding: .minute, value: intervalMinutes, to: cursor)
                else { break }
                cursor = next
            }
            let nextTick = min(cursor, closing)
            return ([now], nextTick)
        }

        let rawWindowEnd =
            calendar.date(byAdding: .minute, value: windowMinutes, to: now)
            ?? now.addingTimeInterval(Double(windowMinutes) * 60)
        let windowEnd = min(rawWindowEnd, closing)

        var dates: [Date] = [now]
        var cursor = opening
        while cursor <= windowEnd {
            if cursor > now {
                dates.append(cursor)
            }
            guard let next = calendar.date(byAdding: .minute, value: intervalMinutes, to: cursor)
            else { break }
            cursor = next
        }

        if windowEnd >= closing {
            if let last = dates.last, last < closing {
                dates.append(closing)
            }
            return (dates, nextMidnight)
        }

        // Reload when the last scheduled tick becomes active so the next window has no stale gap.
        let reloadDate =
            if let last = dates.last, last > now {
                last
            } else {
                windowEnd
            }
        return (dates, reloadDate)
    }

    /// Builds the exact entry list and reload date for `DailyTimelineProvider.getTimeline`.
    static func plan(
        at now: Date,
        selection: DailyTimelineWidgetState.Selection,
        preferFastToday: Bool = false,
        calendar: Calendar = ClinicDate.calendar,
        loadDay: (ScheduleDay, Date) -> WidgetDaySnapshot?
    ) -> DailyTimelinePlan {
        if let resetAt = selection.resetAt {
            // Keep browsed timelines to 1 entry (1 day read, 1 archived view) for minimal tap
            // latency, relying on `.after(resetAt)` to return to Today at expiry or midnight.
            let snapshot = loadDay(selection.day, now)
            return DailyTimelinePlan(
                entries: [DailyTimelinePlan.Entry(date: now, snapshot: snapshot)],
                reloadDate: resetAt
            )
        }

        if let snapshot = loadDay(selection.day, now) {
            let schedule = todayEntryDates(
                from: now,
                preferFastReturn: preferFastToday,
                calendar: calendar
            )
            let entries = schedule.entryDates.map { date in
                DailyTimelinePlan.Entry(date: date, snapshot: snapshot)
            }
            return DailyTimelinePlan(entries: entries, reloadDate: schedule.reloadDate)
        }

        let retryDate =
            calendar.date(byAdding: .minute, value: 30, to: now)
            ?? now.addingTimeInterval(30 * 60)
        return DailyTimelinePlan(
            entries: [DailyTimelinePlan.Entry(date: now, snapshot: nil)],
            reloadDate: retryDate
        )
    }
}

nonisolated struct DailyTimelinePlan: Sendable {
    struct Entry: Sendable {
        let date: Date
        let displayDate: Date
        let snapshot: WidgetDaySnapshot?

        init(date: Date, displayDate: Date? = nil, snapshot: WidgetDaySnapshot?) {
            self.date = date
            self.displayDate = displayDate ?? date
            self.snapshot = snapshot
        }
    }

    let entries: [Entry]
    let reloadDate: Date

    /// Shifts WidgetKit scheduling dates to start at `realNow` while preserving `displayDate`,
    /// so DEBUG morning-clock overrides stay strictly in the future and are not dropped by chronod.
    func shifted(to realNow: Date, from simulatedNow: Date) -> Self {
        let shift = realNow.timeIntervalSince(simulatedNow)
        guard shift != 0 else { return self }
        return Self(
            entries: entries.map { entry in
                Entry(
                    date: entry.date.addingTimeInterval(shift),
                    displayDate: entry.displayDate,
                    snapshot: entry.snapshot
                )
            },
            reloadDate: reloadDate.addingTimeInterval(shift)
        )
    }
}
