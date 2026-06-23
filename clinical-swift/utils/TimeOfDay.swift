import Foundation

extension Date {
    var timeOfDay: TimeOfDay {
        TimeOfDay(date: self)
    }

    func minutes(since timeOfDay: TimeOfDay) -> Int {
        return minutes(since: timeOfDay.on(date: self))
    }
}

typealias Minutes = Int

nonisolated struct TimeOfDay: Comparable, Equatable {
    static let midnight = TimeOfDay(0, 0)

    let hour: Int
    let minute: Int

    init(_ hour: Int, _ minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        hour = components.hour ?? 0
        minute = components.minute ?? 0
    }

    static func + (lhs: TimeOfDay, rhs: Int) -> TimeOfDay {
        let minutesPerDay = 24 * 60

        let newTotalMinutes = (lhs.totalMinutes + rhs) % minutesPerDay
        let normalizedMinutes = newTotalMinutes >= 0
        ? newTotalMinutes
        : newTotalMinutes + minutesPerDay

        return TimeOfDay(normalizedMinutes / 60, normalizedMinutes % 60)
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    func minutes(since timeOfDay: TimeOfDay) -> Minutes {
        totalMinutes - timeOfDay.totalMinutes
    }

    var today: Date {
        on(date: .now)
    }

    func on(date: Date, using calendar: Calendar = .autoupdatingCurrent) -> Date {
        date.setTime(hour, minute, using: calendar)
    }

    var totalMinutes: Minutes {
        hour * 60 + minute
    }
}

extension ClosedRange where Bound == TimeOfDay {
    var minutes: Minutes {
        upperBound.minutes(since: lowerBound)
    }
}

extension Range where Bound == TimeOfDay {
    var minutes: Minutes {
        upperBound.minutes(since: lowerBound)
    }
}

/// TimeOfDay formatting extensions.
extension TimeOfDay {
    enum Format {
        case hourOnly
        case full
    }

    func formatted(_ format: Format) -> String {
        switch format {
        case .full:
            today.formatted(date: .omitted, time: .shortened)
        case .hourOnly:
            today.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
        }
    }
}
