import Foundation

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
