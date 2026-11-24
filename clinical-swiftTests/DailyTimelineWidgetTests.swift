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

    @Test func todaySchedulePreGeneratesNowMarkerTicksThroughClosingAndReloadsAtMidnight() throws {
        let now = try Date("2026-07-18T20:35:00+05:30", strategy: .iso8601)
        let expected = try [
            Date("2026-07-18T20:35:00+05:30", strategy: .iso8601),
            Date("2026-07-18T20:40:00+05:30", strategy: .iso8601),
            Date("2026-07-18T20:50:00+05:30", strategy: .iso8601),
            Date("2026-07-18T21:00:00+05:30", strategy: .iso8601),
        ]
        let midnight = try Date("2026-07-19T00:00:00+05:30", strategy: .iso8601)

        let schedule = DailyTimelineSchedule.todayEntryDates(from: now)
        #expect(schedule.entryDates == expected)
        #expect(schedule.reloadDate == midnight)

        let afterClosing = try Date("2026-07-18T21:15:00+05:30", strategy: .iso8601)
        let lateSchedule = DailyTimelineSchedule.todayEntryDates(from: afterClosing)
        #expect(lateSchedule.entryDates == [afterClosing])
        #expect(lateSchedule.reloadDate == midnight)
    }

    @Test func resetScheduleAppendsTodayNowMarkerTicksAfterResetAt() throws {
        let now = try Date("2026-07-18T20:20:00+05:30", strategy: .iso8601)
        let resetAt = try Date("2026-07-18T20:35:00+05:30", strategy: .iso8601)
        let midnight = try Date("2026-07-19T00:00:00+05:30", strategy: .iso8601)

        let schedule = DailyTimelineSchedule.resetEntryDates(at: now, resetAt: resetAt)
        #expect(schedule.selectedDate == now)
        #expect(
            schedule.resetEntryDates == [
                resetAt,
                try Date("2026-07-18T20:40:00+05:30", strategy: .iso8601),
                try Date("2026-07-18T20:50:00+05:30", strategy: .iso8601),
                try Date("2026-07-18T21:00:00+05:30", strategy: .iso8601),
            ])
        #expect(schedule.reloadDate == midnight)

        // When resetAt is midnight, the appended ticks cover the next day's clinic hours.
        let lateNow = try Date("2026-07-18T23:55:00+05:30", strategy: .iso8601)
        let nextDayMidnight = try Date("2026-07-20T00:00:00+05:30", strategy: .iso8601)
        let midnightSchedule = DailyTimelineSchedule.resetEntryDates(at: lateNow, resetAt: midnight)
        #expect(midnightSchedule.selectedDate == lateNow)
        #expect(midnightSchedule.resetEntryDates.first == midnight)
        #expect(
            midnightSchedule.resetEntryDates.last
                == (try Date("2026-07-19T21:00:00+05:30", strategy: .iso8601)))
        #expect(midnightSchedule.reloadDate == nextDayMidnight)
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
