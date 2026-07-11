import Dependencies
import Foundation

nonisolated enum AppointmentMessageKind: String, CaseIterable, Identifiable, Sendable {
    case confirmation
    case reminder

    var id: Self { self }

    var title: String {
        switch self {
        case .confirmation:
            "Confirmation"
        case .reminder:
            "Reminder"
        }
    }
}

nonisolated struct AppointmentMessageFormatter: Sendable {
    let kind: AppointmentMessageKind
    let details: AppointmentDetails
    let includesLocation: Bool
    let now: Date
    let calendar: Calendar

    func message() -> String {
        let greeting = patientName.map { "Hello \($0)," } ?? "Hello,"
        let body =
            switch kind {
            case .confirmation:
                "Your appointment with \(Bitehaus.doctor) at \(Bitehaus.clinicName) is confirmed \(dateClause) at \(time).\(locationLine)"
            case .reminder:
                "This is a gentle reminder that you have an appointment with \(Bitehaus.doctor) at \(Bitehaus.clinicName) \(dateClause) at \(time).\(locationLine)"
            }

        return """
            \(greeting)

            \(body)

            Best Regards 🙏
            """
    }

    private var patientName: String? {
        guard let name = details.patient.name?.nilIfBlank else {
            return nil
        }

        return name.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    private var dateClause: String {
        guard !calendar.isDate(details.appointment.start, inSameDayAs: now) else {
            return "for today"
        }

        let weekday = details.appointment.start.formatted(
            Date.FormatStyle()
                .weekday(.abbreviated)
                .locale(Locale(identifier: "en_US_POSIX"))
        )
        let month = details.appointment.start.formatted(
            Date.FormatStyle()
                .month(.abbreviated)
                .locale(Locale(identifier: "en_US_POSIX"))
        )
        let day = calendar.component(.day, from: details.appointment.start)
        return "on \(weekday), \(day) \(month)"
    }

    private var time: String {
        let components = calendar.dateComponents([.hour, .minute], from: details.appointment.start)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        let displayMinute = minute < 10 ? "0\(minute)" : "\(minute)"
        let period = hour < 12 ? "AM" : "PM"
        return "\(displayHour):\(displayMinute) \(period)"
    }

    private var locationLine: String {
        guard includesLocation else { return "" }
        return "\n\nLocation: \(Bitehaus.mapLink)"
    }
}
