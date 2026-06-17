import Foundation

nonisolated struct Bitehaus {
    static let startTime = TimeOfDay.init(9, 0)
    static let closingTime = TimeOfDay.init(21, 0)
    static let doctor = "Dr. Monica Mulchandani"
    static let clinicName = "Bitehaus Dental Clinic"
    static let clinicLocation = "https://maps.app.goo.gl/osLykQdZYhJiqBEJ6"
    static let openingMonth = DateComponents(year: 2023, month: 8)
    static let breakBlock = BreakBlock.init(
        startTime: .init(13, 0),
        endTime: .init(16, 0),
        title: "Break"
    )
}
