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
        let greeting = details.patient.firstNameWithHonorific.map { "Hello \($0)," } ?? "Hello,"
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

    private var dateClause: String {
        guard !calendar.isDate(details.appointment.start, inSameDayAs: now) else {
            return "for today"
        }

        let formattedDate = details.appointment.start.formatted(
            Date.FormatStyle(
                locale: calendar.locale ?? .autoupdatingCurrent,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
            .weekday(.abbreviated)
            .day()
            .month(.abbreviated)
        )
        return "on \(formattedDate)"
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
