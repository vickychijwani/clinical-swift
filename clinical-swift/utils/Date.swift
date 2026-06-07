import Foundation

extension Date {
    func setTime(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: self
        )!
    }

    func minutes(since date: Date) -> Int {
        return Int(self.timeIntervalSince(date)) / 60
    }
}
