import Foundation

extension Date {
    nonisolated func startOfDay(using calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.startOfDay(for: self)
    }

    nonisolated func startOfWeek(using calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: self)?.start.startOfDay(using: calendar) ?? startOfDay(using: calendar)
    }

    nonisolated func weekDates(using calendar: Calendar = .autoupdatingCurrent) -> [Date] {
        let weekStart = startOfWeek(using: calendar)

        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)?.startOfDay(using: calendar)
        }
    }

    nonisolated func date(byAddingWeeks weeks: Int, using calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(byAdding: .weekOfYear, value: weeks, to: self)?.startOfDay(using: calendar) ?? startOfDay(using: calendar)
    }

    nonisolated func setTime(_ hour: Int, _ minute: Int, using calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: self
        ) ?? self
    }

    nonisolated func minutes(since date: Date) -> Int {
        return Int(self.timeIntervalSince(date)) / 60
    }
}
