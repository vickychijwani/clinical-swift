import Foundation

nonisolated enum ClinicalURL: Equatable, Sendable {
    case bookAppointment
    case appointment(Appointment.ID)
    case schedule(ScheduleDay)

    init?(_ url: URL) {
        guard
            url.scheme?.lowercased() == "clinical",
            url.user == nil,
            url.password == nil,
            url.port == nil,
            url.fragment == nil
        else {
            return nil
        }

        switch url.host?.lowercased() {
        case "appointments":
            guard url.query == nil else { return nil }

            if url.path == "/book" {
                self = .bookAppointment
                return
            }

            let pathComponents = url.path.split(separator: "/")
            guard
                pathComponents.count == 1,
                let id = UUID(uuidString: String(pathComponents[0]))
            else {
                return nil
            }
            self = .appointment(id)

        case "schedule":
            guard url.path.isEmpty || url.path == "/" else { return nil }
            guard
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                components.queryItems?.count == 1,
                let item = components.queryItems?.first,
                item.name == "date",
                let value = item.value,
                let day = ScheduleDay(value)
            else {
                return nil
            }
            self = .schedule(day)

        default:
            return nil
        }
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = "clinical"

        switch self {
        case .bookAppointment:
            components.host = "appointments"
            components.path = "/book"
        case .appointment(let id):
            components.host = "appointments"
            components.path = "/\(id.uuidString.lowercased())"
        case .schedule(let day):
            components.host = "schedule"
            components.queryItems = [URLQueryItem(name: "date", value: day.description)]
        }

        return components.url
    }
}

nonisolated struct ScheduleDay: Equatable, Hashable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        guard
            (1...9999).contains(year),
            (1...12).contains(month),
            (1...31).contains(day)
        else {
            return nil
        }

        let calendar = Calendar.current
        guard
            let date = calendar.date(
                from: DateComponents(year: year, month: month, day: day)
            )
        else {
            return nil
        }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else {
            return nil
        }

        self.year = year
        self.month = month
        self.day = day
    }

    init?(_ value: String) {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            parts[0].count == 4,
            parts[1].count == 2,
            parts[2].count == 2,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
    }

    func date(using calendar: Calendar) -> Date? {
        guard
            let date = calendar.date(
                from: DateComponents(year: year, month: month, day: day)
            )
        else {
            return nil
        }

        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    var description: String {
        "\(Self.padded(year, length: 4))-\(Self.padded(month, length: 2))-\(Self.padded(day, length: 2))"
    }

    private static func padded(_ value: Int, length: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(length - digits.count, 0)) + digits
    }
}
