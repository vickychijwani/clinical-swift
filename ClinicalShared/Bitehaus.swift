import ClinicalModels
import Foundation

nonisolated struct Bitehaus {
    static let opening = TimeOfDay.init(9, 0)
    static let closing = TimeOfDay.init(21, 0)
    static let preferredFirstShiftStart = TimeOfDay.init(10, 0)
    static let preferredSecondShiftStart = TimeOfDay.init(16, 30)
    static let doctor = "Dr. Monica Mulchandani"
    static let clinicName = "Bitehaus Dental Clinic"
    static let mapLink = "https://maps.app.goo.gl/M3cuCEojHWQQ1NkC7"
    static let openingMonth = DateComponents(year: 2023, month: 8)
    static let `break` = BreakBlock.init(
        start: .init(13, 0),
        end: .init(16, 0),
        title: "Break"
    )

    /// Derived properties, based on intrinsic properties above
    static let firstHalf = Bitehaus.opening...Bitehaus.break.start
    static let secondHalf = Bitehaus.break.end...Bitehaus.closing

    /// Returns the next clinic working day after `date` by skipping Sunday (weekday 1).
    static func nextBusinessDay(after date: Date, using calendar: Calendar) -> Date {
        let nextDay = date.date(byAddingDays: 1, using: calendar)
        if calendar.component(.weekday, from: nextDay) == 1 {
            return nextDay.date(byAddingDays: 1, using: calendar)
        }
        return nextDay
    }
}

nonisolated struct BreakBlock {
    let start: TimeOfDay
    let end: TimeOfDay
    let title: String
}
