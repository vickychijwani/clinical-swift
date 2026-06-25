import Foundation
import Testing

@testable import clinical_swift

struct TimeOfDayTests {
    @Test func ordersByHourThenMinute() {
        #expect(TimeOfDay(8, 59) < TimeOfDay(9, 0))
        #expect(TimeOfDay(9, 15) < TimeOfDay(9, 30))
        #expect(!(TimeOfDay(9, 30) < TimeOfDay(9, 30)))
    }

    @Test func calculatesMinuteDistanceWithinClinicDay() {
        #expect(TimeOfDay(9, 30).minutes(since: TimeOfDay(9, 0)) == 30)
        #expect(TimeOfDay(13, 0).minutes(since: TimeOfDay(9, 30)) == 210)
        #expect(TimeOfDay(9, 0).minutes(since: TimeOfDay(13, 0)) == -240)
    }

    @Test func calculatesMinuteDistanceAtDayEdges() {
        #expect(TimeOfDay(23, 59).minutes(since: .midnight) == 1_439)
        #expect(TimeOfDay.midnight.minutes(since: TimeOfDay(23, 59)) == -1_439)
    }

    @Test func extractsHourAndMinuteWithExplicitCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone

        let date = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 6,
                    day: 8,
                    hour: 14,
                    minute: 45,
                    second: 30
                )
            ))

        #expect(TimeOfDay(date: date, calendar: calendar) == TimeOfDay(14, 45))
    }

    @Test func appliesTimeOfDayToExistingDate() {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 804_600_000)
        let updatedDate = TimeOfDay(16, 20).on(date: referenceDate)
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: updatedDate
        )

        #expect(components.hour == 16)
        #expect(components.minute == 20)
        #expect(components.second == 0)
    }

    @Test func dateMinutesSinceTimeOfDayUsesDateCalendarDay() {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 804_600_000)
        let appointmentStart = TimeOfDay(10, 15).on(date: referenceDate)

        #expect(appointmentStart.minutes(since: TimeOfDay(9, 0)) == 75)
    }
}
