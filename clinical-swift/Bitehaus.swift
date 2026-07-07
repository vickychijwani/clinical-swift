import Foundation

nonisolated struct Bitehaus {
    static let opening = TimeOfDay.init(9, 0)
    static let closing = TimeOfDay.init(21, 0)
    static let preferredFirstShiftStart = TimeOfDay.init(10, 0)
    static let preferredSecondShiftStart = TimeOfDay.init(16, 30)
    static let doctor = "Dr. Monica Mulchandani"
    static let clinicName = "Bitehaus Dental Clinic"
    static let clinicLocation = "https://maps.app.goo.gl/osLykQdZYhJiqBEJ6"
    static let openingMonth = DateComponents(year: 2023, month: 8)
    static let `break` = BreakBlock.init(
        start: .init(13, 0),
        end: .init(16, 0),
        title: "Break"
    )

    /// Derived properties, based on intrinsic properties above
    static let firstHalf = Bitehaus.opening...Bitehaus.break.start
    static let secondHalf = Bitehaus.break.end...Bitehaus.closing
}

nonisolated struct BreakBlock {
    let start: TimeOfDay
    let end: TimeOfDay
    let title: String
}
