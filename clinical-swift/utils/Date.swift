import Foundation

extension Date {
    func setTime(_ hour: Int, _ minute: Int) -> Date {
        return TimeMarker.time(hour, minute).on(date: self)
    }

    func minutes(since timeMarker: TimeMarker) -> Int {
        return minutes(since: timeMarker.on(date: self))
    }

    func minutes(since date: Date) -> Int {
        return abs(Int(self.timeIntervalSince(date)) / 60)
    }
}

enum TimeMarker {
    case midnight
    case time(_ hour: Int, _ minute: Int)
    
    var hour: Int {
        return switch self {
        case .midnight:
            12
        case .time(let hour, _):
            hour
        }
    }

    func on(date: Date) -> Date {
        return switch self {
        case .midnight:
            Calendar.current.startOfDay(for: date)
        case .time(let hour, let minute):
            Calendar.current.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: date
            )!
        }
    }
}
