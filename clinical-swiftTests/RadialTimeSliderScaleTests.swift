import Testing
@testable import clinical_swift

struct RadialTimeSliderScaleTests {
    private let scale = RadialTimeSliderScale(
        range: TimeOfDay(9, 0)...TimeOfDay(20, 30),
        stepMinutes: 5
    )

    @Test func generatesConfiguredRangeInFiveMinuteSteps() {
        #expect(scale.maximumIndex == 138)
        #expect(scale.time(at: 0) == TimeOfDay(9, 0))
        #expect(scale.time(at: 138) == TimeOfDay(20, 30))
    }

    @Test func snapsToNearestRepresentableTime() {
        #expect(scale.index(for: TimeOfDay(10, 3)) == 13)
        #expect(scale.time(at: 13) == TimeOfDay(10, 5))
    }

    @Test func clampsTimesAndIndicesAtEndpoints() {
        #expect(scale.index(for: TimeOfDay(8, 0)) == 0)
        #expect(scale.index(for: TimeOfDay(21, 0)) == 138)
        #expect(scale.time(at: -1) == TimeOfDay(9, 0))
        #expect(scale.time(at: 139) == TimeOfDay(20, 30))
    }

    @Test func identifiesHourTicks() {
        #expect(scale.isMajorTick(at: 12))
        #expect(!scale.isMajorTick(at: 13))
    }

    @Test func draggingLeftAdvancesAndDraggingRightRewinds() {
        #expect(scale.stepOffset(forTranslation: -20, pointsPerStep: 10) == 2)
        #expect(scale.stepOffset(forTranslation: 20, pointsPerStep: 10) == -2)
    }
}
