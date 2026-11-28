import ClinicalModels
import CoreGraphics
import Foundation
import Testing

@testable import clinical_swift

struct DailyTimelineWidgetTests {
    @Test func stateStepsConsecutiveDaysIncludingSundaysAndAutoResets() throws {
        let suiteName = "DailyTimelineWidgetTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let state = DailyTimelineWidgetState(suiteName: suiteName)

        // Saturday, 18 Jul 2026 at 10:00 IST.
        let saturdayMorning = try Date("2026-07-18T10:00:00+05:30", strategy: .iso8601)
        let saturday = ScheduleDay(date: saturdayMorning, calendar: ClinicDate.calendar)
        let sunday = try #require(ScheduleDay(year: 2026, month: 7, day: 19))
        let friday = try #require(ScheduleDay(year: 2026, month: 7, day: 17))

        #expect(state.selection(at: saturdayMorning) == .init(day: saturday, resetAt: nil))

        // Stepping forward lands on Sunday without skipping.
        let steppedForward = state.step(byDays: 1, at: saturdayMorning)
        #expect(steppedForward == sunday)
        let sundaySelection = state.selection(at: saturdayMorning)
        #expect(sundaySelection.day == sunday)
        #expect(
            sundaySelection.resetAt
                == saturdayMorning.addingTimeInterval(DailyTimelineWidgetState.idleResetInterval))

        // Stepping back to Today clears the override.
        #expect(state.step(byDays: -1, at: saturdayMorning) == saturday)
        #expect(state.selection(at: saturdayMorning) == .init(day: saturday, resetAt: nil))

        // Stepping backward into past days works and expires after 15 minutes.
        #expect(state.step(byDays: -1, at: saturdayMorning) == friday)
        let afterTimeout = saturdayMorning.addingTimeInterval(
            DailyTimelineWidgetState.idleResetInterval)
        #expect(state.selection(at: afterTimeout) == .init(day: saturday, resetAt: nil))

        // Near midnight, expiry is persisted with the midnight cap so reads after midnight return Today.
        let lateNight = try Date("2026-07-18T23:55:00+05:30", strategy: .iso8601)
        let midnight = try Date("2026-07-19T00:00:00+05:30", strategy: .iso8601)
        let afterMidnight = try Date("2026-07-19T00:01:00+05:30", strategy: .iso8601)
        #expect(state.step(byDays: -1, at: lateNight) == friday)
        #expect(state.selection(at: lateNight) == .init(day: friday, resetAt: midnight))
        #expect(state.selection(at: afterMidnight) == .init(day: sunday, resetAt: nil))

        state.resetToToday()
        #expect(state.selection(at: lateNight) == .init(day: saturday, resetAt: nil))
    }

    @Test func todayScheduleUsesShortRollingWindowAndReloadsAtWindowEndOrMidnight() throws {
        // Before clinic opening: include opening without extra pre-opening reloads.
        let earlyMorning = try Date("2026-07-18T07:15:00+05:30", strategy: .iso8601)
        let opening = try Date("2026-07-18T09:00:00+05:30", strategy: .iso8601)
        let earlySchedule = DailyTimelineSchedule.todayEntryDates(from: earlyMorning)
        #expect(earlySchedule.entryDates == [earlyMorning, opening])
        #expect(earlySchedule.reloadDate == opening)

        // Mid-morning: emit only a short rolling window and reload at the last tick.
        let morning = try Date("2026-07-18T09:25:00+05:30", strategy: .iso8601)
        let morningSchedule = DailyTimelineSchedule.todayEntryDates(from: morning)
        #expect(
            morningSchedule.entryDates == [
                morning,
                try Date("2026-07-18T09:30:00+05:30", strategy: .iso8601),
                try Date("2026-07-18T09:40:00+05:30", strategy: .iso8601),
                try Date("2026-07-18T09:50:00+05:30", strategy: .iso8601),
                try Date("2026-07-18T10:00:00+05:30", strategy: .iso8601),
                try Date("2026-07-18T10:10:00+05:30", strategy: .iso8601),
                try Date("2026-07-18T10:20:00+05:30", strategy: .iso8601),
                try Date("2026-07-18T10:30:00+05:30", strategy: .iso8601),
                try Date("2026-07-18T10:40:00+05:30", strategy: .iso8601),
                try Date("2026-07-18T10:50:00+05:30", strategy: .iso8601),
            ])
        #expect(
            morningSchedule.reloadDate
                == (try Date("2026-07-18T10:50:00+05:30", strategy: .iso8601)))

        // Within the final window before closing: cover through closing and reload at midnight.
        let nearClosing = try Date("2026-07-18T20:35:00+05:30", strategy: .iso8601)
        let midnight = try Date("2026-07-19T00:00:00+05:30", strategy: .iso8601)
        let closingSchedule = DailyTimelineSchedule.todayEntryDates(from: nearClosing)
        #expect(
            closingSchedule.entryDates == [
                nearClosing,
                try Date("2026-07-18T20:40:00+05:30", strategy: .iso8601),
                try Date("2026-07-18T20:50:00+05:30", strategy: .iso8601),
                try Date("2026-07-18T21:00:00+05:30", strategy: .iso8601),
            ])
        #expect(closingSchedule.reloadDate == midnight)

        // After clinic closing: single entry until next clinic midnight.
        let afterClosing = try Date("2026-07-18T21:15:00+05:30", strategy: .iso8601)
        let lateSchedule = DailyTimelineSchedule.todayEntryDates(from: afterClosing)
        #expect(lateSchedule.entryDates == [afterClosing])
        #expect(lateSchedule.reloadDate == midnight)
    }

    @Test func browsedTimelineReturnsToTodayAfter15MinutesAndAtClinicMidnight() throws {
        let suiteName = "DailyTimelineWidgetTests.plan.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let state = DailyTimelineWidgetState(suiteName: suiteName)

        let saturdayMorning = try Date("2026-07-18T10:00:00+05:30", strategy: .iso8601)
        let idleResetAt = try Date("2026-07-18T10:15:00+05:30", strategy: .iso8601)
        let saturday = ScheduleDay(date: saturdayMorning, calendar: ClinicDate.calendar)
        let sunday = try #require(ScheduleDay(year: 2026, month: 7, day: 19))
        let friday = try #require(ScheduleDay(year: 2026, month: 7, day: 17))

        // Step forward to Sunday: timeline emits 1 entry using 1 day read and schedules reload at resetAt.
        state.step(byDays: 1, at: saturdayMorning)
        var loadCount = 0
        let browsedPlan = DailyTimelineSchedule.plan(
            at: saturdayMorning,
            selection: state.selection(at: saturdayMorning),
            loadDay: { day, date in
                loadCount += 1
                return snapshot(day: day, at: date)
            }
        )
        #expect(loadCount == 1)
        #expect(browsedPlan.entries.count == 1)
        #expect(browsedPlan.entries[0].date == saturdayMorning)
        #expect(browsedPlan.entries[0].snapshot?.day == sunday)
        #expect(browsedPlan.entries[0].snapshot?.isToday == false)
        #expect(browsedPlan.reloadDate == idleResetAt)

        // When the .after(resetAt) reload runs at 10:15, state has expired and Today resumes.
        let afterIdleReload = DailyTimelineSchedule.plan(
            at: browsedPlan.reloadDate,
            selection: state.selection(at: browsedPlan.reloadDate),
            loadDay: { day, date in snapshot(day: day, at: date) }
        )
        #expect(afterIdleReload.entries.first?.date == idleResetAt)
        #expect(
            afterIdleReload.entries.allSatisfy {
                $0.snapshot?.day == saturday && $0.snapshot?.isToday == true
            })
        #expect(afterIdleReload.entries.count <= 10)

        // Near clinic midnight: browsed timeline schedules reload at 00:00,
        // and the midnight reload switches to the new Today (Sunday) until clinic opening.
        let lateNight = try Date("2026-07-18T23:55:00+05:30", strategy: .iso8601)
        let midnight = try Date("2026-07-19T00:00:00+05:30", strategy: .iso8601)
        let sundayOpening = try Date("2026-07-19T09:00:00+05:30", strategy: .iso8601)
        state.step(byDays: -1, at: lateNight)
        let midnightPlan = DailyTimelineSchedule.plan(
            at: lateNight,
            selection: state.selection(at: lateNight),
            loadDay: { day, date in snapshot(day: day, at: date) }
        )
        #expect(midnightPlan.entries.count == 1)
        #expect(midnightPlan.entries[0].date == lateNight)
        #expect(midnightPlan.entries[0].snapshot?.day == friday)
        #expect(midnightPlan.entries[0].snapshot?.isToday == false)
        #expect(midnightPlan.reloadDate == midnight)

        let afterMidnightReload = DailyTimelineSchedule.plan(
            at: midnight,
            selection: state.selection(at: midnight),
            loadDay: { day, date in snapshot(day: day, at: date) }
        )
        #expect(afterMidnightReload.entries.map(\.date) == [midnight, sundayOpening])
        #expect(
            afterMidnightReload.entries.allSatisfy {
                $0.snapshot?.day == sunday && $0.snapshot?.isToday == true
            })
        #expect(afterMidnightReload.reloadDate == sundayOpening)
    }

    @Test func nowMarkerAdvancesAcrossFullClinicDayViaRollingReloads() throws {
        let opening = try Date("2026-07-18T09:00:00+05:30", strategy: .iso8601)
        let closing = try Date("2026-07-18T21:00:00+05:30", strategy: .iso8601)
        let midnight = try Date("2026-07-19T00:00:00+05:30", strategy: .iso8601)
        let today = ScheduleDay(date: opening, calendar: ClinicDate.calendar)
        let items = [
            appointment(startHour: 10, startMinute: 0, duration: 45),
            appointment(startHour: 17, startMinute: 0, duration: 30),
        ]

        var cursor = opening
        var reloadCount = 0
        var seenDates: Set<Date> = []

        while cursor < midnight {
            reloadCount += 1
            #expect(reloadCount <= 12)
            let plan = DailyTimelineSchedule.plan(
                at: cursor,
                selection: .init(day: today, resetAt: nil),
                loadDay: { day, date in snapshot(day: day, at: date, items: items) }
            )
            // Keep each reload small to prevent archiving the full clinic day up front.
            #expect(plan.entries.count <= 10)
            #expect(plan.reloadDate > cursor)
            for entry in plan.entries {
                seenDates.insert(entry.date)
            }
            cursor = plan.reloadDate
        }

        #expect(reloadCount == 8)

        // Verify every 10-minute clinic tick is scheduled and the Now marker moves downward monotonically.
        var previousY: CGFloat = -1
        var tick = opening
        while tick < closing {
            #expect(seenDates.contains(tick))
            let scale = TimelineScale.widget(items: items, now: tick, availableHeight: 520)
            #expect(scale.showsTime(tick.timeOfDay))
            let y = scale.yOffset(for: tick.timeOfDay)
            #expect(y > previousY)
            previousY = y
            tick = try #require(ClinicDate.calendar.date(byAdding: .minute, value: 10, to: tick))
        }

        // Closing entry is scheduled and hides the Now marker.
        #expect(seenDates.contains(closing))
        let closingScale = TimelineScale.widget(items: items, now: closing, availableHeight: 520)
        #expect(!closingScale.showsTime(closing.timeOfDay))
    }

    #if DEBUG
        @Test func debugMorningClockOverrideKeepsShiftedEntriesFutureAtNight() throws {
            let suiteName = "DailyTimelineWidgetTests.debugClock.\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suiteName) }
            let state = DailyTimelineWidgetState(suiteName: suiteName)
            state.setDebugTimeOfDayMinutes(9 * 60 + 30)

            let lateNight = try Date("2026-07-18T23:30:00+05:30", strategy: .iso8601)
            let expectedMorning = try Date("2026-07-18T09:30:00+05:30", strategy: .iso8601)
            let simulatedNow = state.effectiveNow(from: lateNight)
            #expect(simulatedNow == expectedMorning)

            let shifted = DailyTimelineSchedule.plan(
                at: simulatedNow,
                selection: state.selection(at: simulatedNow),
                loadDay: { day, date in snapshot(day: day, at: date) }
            )
            .shifted(to: lateNight, from: simulatedNow)

            // Every shifted WidgetKit date is >= real wall-clock time so chronod archives all 10 morning entries.
            #expect(shifted.entries.count == 10)
            #expect(shifted.entries.first?.date == lateNight)
            #expect(shifted.entries.first?.displayDate == expectedMorning)
            #expect(shifted.entries.allSatisfy { $0.date >= lateNight })
            #expect(
                shifted.entries.last?.displayDate
                    == (try Date("2026-07-18T11:00:00+05:30", strategy: .iso8601)))
            #expect(shifted.reloadDate > lateNight)

            state.setDebugTimeOfDayMinutes(nil)
            #expect(state.effectiveNow(from: lateNight) == lateNight)
        }
    #endif

    @Test func interactiveReturnToTodayUsesOneEntryThenBackgroundReloadBuildsRollingWindow()
        throws
    {
        let suiteName = "DailyTimelineWidgetTests.fastToday.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let state = DailyTimelineWidgetState(suiteName: suiteName)

        let morning = try Date("2026-07-18T09:25:00+05:30", strategy: .iso8601)
        let nextTick = try Date("2026-07-18T09:30:00+05:30", strategy: .iso8601)
        let saturday = ScheduleDay(date: morning, calendar: ClinicDate.calendar)

        state.step(byDays: 1, at: morning)
        state.resetToToday()
        #expect(state.consumeFastTodayPending())
        #expect(!state.consumeFastTodayPending())

        let fastPlan = DailyTimelineSchedule.plan(
            at: morning,
            selection: state.selection(at: morning),
            preferFastToday: true,
            loadDay: { day, date in snapshot(day: day, at: date) }
        )
        #expect(fastPlan.entries.map(\.date) == [morning])
        #expect(fastPlan.entries.first?.snapshot?.day == saturday)
        #expect(fastPlan.entries.first?.snapshot?.isToday == true)
        #expect(fastPlan.reloadDate == nextTick)

        // The background reload at nextTick runs with preferFastToday == false and builds the rolling window.
        let backgroundPlan = DailyTimelineSchedule.plan(
            at: fastPlan.reloadDate,
            selection: state.selection(at: fastPlan.reloadDate),
            preferFastToday: state.consumeFastTodayPending(),
            loadDay: { day, date in snapshot(day: day, at: date) }
        )
        #expect(backgroundPlan.entries.count == 10)
        #expect(backgroundPlan.entries.first?.date == nextTick)

        // Near closing (8:55 PM): fast return still schedules reload at closing (9:00 PM) so the
        // Now marker clears on time instead of lingering until midnight.
        let nearClosing = try Date("2026-07-18T20:55:00+05:30", strategy: .iso8601)
        let closing = try Date("2026-07-18T21:00:00+05:30", strategy: .iso8601)
        let midnight = try Date("2026-07-19T00:00:00+05:30", strategy: .iso8601)
        let closingFastPlan = DailyTimelineSchedule.plan(
            at: nearClosing,
            selection: .init(day: saturday, resetAt: nil),
            preferFastToday: true,
            loadDay: { day, date in snapshot(day: day, at: date) }
        )
        #expect(closingFastPlan.entries.map(\.date) == [nearClosing])
        #expect(closingFastPlan.reloadDate == closing)

        let atClosingReload = DailyTimelineSchedule.plan(
            at: closing,
            selection: .init(day: saturday, resetAt: nil),
            preferFastToday: false,
            loadDay: { day, date in snapshot(day: day, at: date) }
        )
        #expect(atClosingReload.entries.map(\.date) == [closing])
        #expect(atClosingReload.reloadDate == midnight)
    }

    @Test func concurrentStepsPreserveEveryTap() async throws {
        let suiteName = "DailyTimelineWidgetTests.concurrent.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let state = DailyTimelineWidgetState(suiteName: suiteName)
        let morning = try Date("2026-07-18T10:00:00+05:30", strategy: .iso8601)
        let threeDaysLater = try #require(ScheduleDay(year: 2026, month: 7, day: 21))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    _ = state.step(byDays: 1, at: morning)
                }
            }
        }
        #expect(state.selection(at: morning).day == threeDaysLater)
    }

    @Test func widgetScaleFitsExactHeightAndTrimsUnusedOuterHoursOnlyWhenBreakExpanded() throws {
        let availableHeight: CGFloat = 520
        let normalItems = [
            appointment(startHour: 10, startMinute: 0, duration: 45),
            appointment(startHour: 17, startMinute: 0, duration: 30),
        ]
        let compactScale = TimelineScale.widget(
            items: normalItems,
            now: nil,
            availableHeight: availableHeight
        )
        #expect(!compactScale.isBreakExpanded)
        #expect(compactScale.visibleOpening == TimeOfDay(9, 0))
        #expect(compactScale.visibleClosing == TimeOfDay(21, 0))
        #expect(
            abs(
                (compactScale.totalHeight + compactScale.metrics.verticalPadding * 2)
                    - availableHeight)
                < 0.01)
        #expect(compactScale.showsTime(TimeOfDay(14, 30)))
        #expect(
            abs(
                compactScale.yOffset(for: TimeOfDay(14, 30))
                    - (compactScale.yOffset(for: Bitehaus.break.start) + compactScale.breakHeight
                        / 2)
            ) < 0.001)
        #expect(!compactScale.showsTime(TimeOfDay(8, 59)))
        #expect(!compactScale.showsTime(TimeOfDay(21, 0)))

        // Break item only: both outer hours (9–10 AM and 8–9 PM) trim.
        let breakOnlyItems = [
            appointment(startHour: 14, startMinute: 0, duration: 15)
        ]
        let trimmedScale = TimelineScale.widget(
            items: breakOnlyItems,
            now: try Date("2026-07-18T14:05:00+05:30", strategy: .iso8601),
            availableHeight: availableHeight
        )
        #expect(trimmedScale.isBreakExpanded)
        #expect(trimmedScale.visibleOpening == TimeOfDay(10, 0))
        #expect(trimmedScale.visibleClosing == TimeOfDay(20, 0))
        #expect(trimmedScale.hourMarkers.map(\.hour) == Array(10...20))
        #expect(
            abs(
                (trimmedScale.totalHeight + trimmedScale.metrics.verticalPadding * 2)
                    - availableHeight)
                < 0.01)
        #expect(trimmedScale.showsTime(TimeOfDay(14, 30)))
        #expect(
            abs(
                trimmedScale.yOffset(for: TimeOfDay(14, 30))
                    - (trimmedScale.yOffset(for: Bitehaus.break.start)
                        + trimmedScale.metrics.height(for: 90))
            ) < 0.001)
        #expect(trimmedScale.height(from: TimeOfDay(14, 0), to: TimeOfDay(14, 15)) > 12)

        // Current time in 9–10 AM keeps opening at 9 AM; item ending after 8 PM keeps closing at 9 PM.
        let earlyNow = try Date("2026-07-18T09:20:00+05:30", strategy: .iso8601)
        let fullSpanItems = [
            appointment(startHour: 14, startMinute: 0, duration: 30),
            appointment(startHour: 19, startMinute: 45, duration: 30),
        ]
        let fullSpanScale = TimelineScale.widget(
            items: fullSpanItems,
            now: earlyNow,
            availableHeight: availableHeight
        )
        #expect(fullSpanScale.isBreakExpanded)
        #expect(fullSpanScale.visibleOpening == TimeOfDay(9, 0))
        #expect(fullSpanScale.visibleClosing == TimeOfDay(21, 0))
        #expect(fullSpanScale.showsTime(earlyNow.timeOfDay))
        #expect(
            abs(
                (fullSpanScale.totalHeight + fullSpanScale.metrics.verticalPadding * 2)
                    - availableHeight)
                < 0.01)
    }

    @Test func widgetLayoutEngineMaintainsOverlapInvariantsWithWidgetMetrics() throws {
        let items = [
            appointment(name: "Aarav Mehta", startHour: 10, startMinute: 0, duration: 60),
            appointment(name: "Mira Shah", startHour: 10, startMinute: 15, duration: 30),
            appointment(name: "Kabir Malhotra", startHour: 10, startMinute: 15, duration: 15),
            appointment(name: "Vivaan Kapoor", startHour: 14, startMinute: 0, duration: 15),
        ]
        let width: CGFloat = 340
        let scale = TimelineScale.widget(items: items, now: nil, availableHeight: 520)
        let contentMetrics = ScheduleCardContentMetrics(configuration: .widget)
        let overlap = ScheduleCardTuning.Overlap.widget
        let layouts = TimelineLayoutEngine(
            availableWidth: width,
            scale: scale,
            overlap: overlap,
            contentMetrics: contentMetrics,
            assertOnFallback: false
        ).layout(items: items)

        #expect(layouts.count == items.count)
        let bounds = HorizontalSpan(
            min: scale.metrics.contentLeadingInset,
            max: scale.metrics.contentLeadingInset
                + scale.metrics.contentWidth(availableWidth: width)
        )
        let entries = layouts.map { info -> ValidatedLayoutEntry in
            let measured = contentMetrics.bounds(
                start: info.item.start,
                label: info.item.displayLabel,
                cardHeight: info.rect.height,
                presentation: info.presentation
            )
            let contentRect = CGRect(
                x: info.rect.minX,
                y: info.rect.minY,
                width: min(info.rect.width, measured.width),
                height: min(info.rect.height, measured.height)
            )
            return ValidatedLayoutEntry(layoutInfo: info, contentRect: contentRect)
        }
        let violations = TimelineLayoutValidator.validate(
            entries: entries,
            bounds: bounds,
            stripWidth: CGFloat(overlap.stripWidth)
        )
        #expect(violations.isEmpty)
    }

    private func snapshot(
        day: ScheduleDay,
        at date: Date,
        items: [TimelineItem] = []
    ) -> WidgetDaySnapshot {
        let dayDate = day.date(using: ClinicDate.calendar) ?? ClinicDate.day(date)
        let today = ScheduleDay(date: date, calendar: ClinicDate.calendar)
        return WidgetDaySnapshot(
            day: day,
            date: dayDate,
            isToday: day == today,
            items: items,
            generatedAt: date,
            calendar: ClinicDate.calendar
        )
    }

    private func appointment(
        name: String = "Patient",
        startHour: Int,
        startMinute: Int,
        duration: Int
    ) -> TimelineItem {
        let day = ClinicDate.day(Date(timeIntervalSinceReferenceDate: 800_000_000))
        return .appointment(
            Appointment(
                id: UUID(),
                patientName: name,
                start: TimeOfDay(startHour, startMinute).on(date: day, using: ClinicDate.calendar),
                durationMinutes: duration,
                status: .scheduled
            )
        )
    }
}
