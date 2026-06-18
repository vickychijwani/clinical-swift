import Foundation

nonisolated struct RadialTimeSliderScale {
    let range: ClosedRange<TimeOfDay>
    let stepMinutes: Int

    init(
        range: ClosedRange<TimeOfDay>,
        stepMinutes: Int
    ) {
        precondition(stepMinutes > 0, "Radial time slider step must be positive.")
        self.range = range
        self.stepMinutes = stepMinutes
    }

    var maximumIndex: Int {
        (range.upperBound.totalMinutes - range.lowerBound.totalMinutes) / stepMinutes
    }

    func time(at index: Int) -> TimeOfDay {
        let clampedIndex = min(max(index, 0), maximumIndex)
        let totalMinutes = range.lowerBound.totalMinutes + clampedIndex * stepMinutes
        return TimeOfDay(totalMinutes / 60, totalMinutes % 60)
    }

    func index(for time: TimeOfDay) -> Int {
        let minutesFromStart = time.totalMinutes - range.lowerBound.totalMinutes
        let nearestIndex = Int((Double(minutesFromStart) / Double(stepMinutes)).rounded())
        return min(max(nearestIndex, 0), maximumIndex)
    }

    func isMajorTick(at index: Int) -> Bool {
        time(at: index).minute == 0
    }

    func stepOffset(
        forTranslation translation: Double,
        pointsPerStep: Double
    ) -> Int {
        guard pointsPerStep > 0 else { return 0 }
        return Int((-translation / pointsPerStep).rounded())
    }
}
