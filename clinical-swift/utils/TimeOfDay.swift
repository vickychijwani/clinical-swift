import Foundation

extension Date {
    var timeOfDay: TimeOfDay {
        TimeOfDay(date: self)
    }

    func minutes(since timeOfDay: TimeOfDay) -> Int {
        return minutes(since: timeOfDay.on(date: self))
    }
}

struct TimeOfDay: Comparable, Equatable {
    let hour: Int
    let minute: Int

    init(_ hour: Int, _ minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        hour = components.hour ?? 0
        minute = components.minute ?? 0
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    func minutes(since timeOfDay: TimeOfDay) -> Int {
        return Int(
            self.on(date: .now).timeIntervalSince(timeOfDay.on(date: .now))
        ) / 60
    }

    var today: Date {
        on(date: .now)
    }

    func on(date: Date) -> Date {
        date.setTime(hour, minute)
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
