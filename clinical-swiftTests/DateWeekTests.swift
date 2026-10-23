import ClinicalModels
import Foundation
import Testing

@testable import clinical_swift

struct DateWeekTests {
    @Test func weekStartFollowsCalendarFirstWeekday() throws {
        let sundayCalendar = fixedCalendar(firstWeekday: 1)
        let date = try #require(sundayCalendar.date(2026, 6, 10, hour: 12))
        let sundayWeekStart = try #require(sundayCalendar.date(2026, 6, 7))

        #expect(date.startOfWeek(using: sundayCalendar) == sundayWeekStart)

        var mondayCalendar = fixedCalendar(firstWeekday: 2)
        mondayCalendar.minimumDaysInFirstWeek =
            sundayCalendar.minimumDaysInFirstWeek
        let mondayWeekStart = try #require(mondayCalendar.date(2026, 6, 8))

        #expect(date.startOfWeek(using: mondayCalendar) == mondayWeekStart)
    }

    @Test func weekDatesContainSevenUniqueCalendarDays() throws {
        let calendar = fixedCalendar(firstWeekday: 1)
        let date = try #require(calendar.date(2026, 6, 10, hour: 12))
        let weekDates = date.weekDates(using: calendar)
        let dayComponents = Set(
            weekDates.map {
                calendar.dateComponents([.year, .month, .day], from: $0)
            }
        )

        #expect(weekDates.count == 7)
        #expect(dayComponents.count == 7)
    }

    @Test func addingWeeksPreservesWeekday() throws {
        let calendar = fixedCalendar(firstWeekday: 1)
        let date = try #require(calendar.date(2026, 6, 10, hour: 12))
        let nextWeek = date.date(byAddingWeeks: 1, using: calendar)

        #expect(
            calendar.component(.weekday, from: nextWeek)
                == calendar.component(.weekday, from: date)
        )
        #expect(calendar.component(.day, from: nextWeek) == 17)
    }

    private func fixedCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        calendar.firstWeekday = firstWeekday
        return calendar
    }
}

extension Calendar {
    /// Convenience helper for tests to build a Date from y/m/d and optional h/m/s
    /// Respects the calendar's locale and timeZone.
    func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) -> Date? {
        date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            )
        )
    }
}
