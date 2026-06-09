import Foundation

extension Date {
    func startOfDay(using calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.startOfDay(for: self)
    }

    func startOfWeek(using calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: self)?.start.startOfDay(using: calendar) ?? startOfDay(using: calendar)
    }

    func weekDates(using calendar: Calendar = .autoupdatingCurrent) -> [Date] {
        let weekStart = startOfWeek(using: calendar)

        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)?.startOfDay(using: calendar)
        }
    }

    func date(byAddingWeeks weeks: Int, using calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(byAdding: .weekOfYear, value: weeks, to: self)?.startOfDay(using: calendar) ?? startOfDay(using: calendar)
    }

    func setTime(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: self
        )!
    }

    func minutes(since date: Date) -> Int {
        return Int(self.timeIntervalSince(date)) / 60
    }
}
