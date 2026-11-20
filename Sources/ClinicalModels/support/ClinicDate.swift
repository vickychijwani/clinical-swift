import Dependencies
import Foundation

/// Clinic dates and times use the Gregorian calendar in Asia/Kolkata with the en_IN locale,
/// regardless of device settings.
public nonisolated enum ClinicDate {
    // This identifier is part of Foundation's time zone database.
    public static let timeZone = TimeZone(identifier: "Asia/Kolkata")!
    public static let locale = Locale(identifier: "en_IN")
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }()

    public static var today: Date {
        @Dependency(\.date.now) var now
        return day(now)
    }

    public static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    public static func nextDay(_ date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: day(date))!
    }

    public static var formatStyle: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
    }

    public static var intervalFormatStyle: Date.IntervalFormatStyle {
        Date.IntervalFormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
    }
}
