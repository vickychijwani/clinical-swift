import SwiftUI

struct ClippedTimeline<Content: View>: View {
    let timeline: Content
    let centerOnTime: TimeOfDay
    let clippedHeight: CGFloat = 240

    init(at centerOnTime: TimeOfDay, @ViewBuilder timeline: () -> Content) {
        self.timeline = timeline()
        self.centerOnTime = centerOnTime
    }

    var body: some View {
        let yOffset = min(
            max(
                yOffsetFor(centerOnTime) - clippedHeight / 2 + Timeline.metrics.hourHeight/2,
                0
            ),
            (yOffsetFor(Bitehaus.closingTime) - clippedHeight + Timeline.metrics
                .verticalPadding
                * 2)
        )
        ClippedView(height: clippedHeight, yOffset: yOffset) {
            timeline
        }
    }

    func yOffsetFor(_ time: TimeOfDay) -> CGFloat {
        switch time {
        case Bitehaus.startTime..<Bitehaus.breakBlock.startTime:
            return Timeline.metrics.pixelsPerMinute
                * CGFloat(time.minutes(since: Bitehaus.startTime))
        case Bitehaus.breakBlock.startTime..<Bitehaus.breakBlock.endTime:
            return Timeline.metrics.pixelsPerMinute
                * CGFloat(
                    Bitehaus.breakBlock.startTime.minutes(since: Bitehaus.startTime)
                )
        case Bitehaus.breakBlock.endTime...TimeOfDay(23, 59):
            return Timeline.metrics.pixelsPerMinute
                * CGFloat(
                    Bitehaus.breakBlock.startTime.minutes(since: Bitehaus.startTime)
                )
                + TimelineBreakView.height + Timeline.metrics.pixelsPerMinute
                * CGFloat(
                    time.minutes(since: Bitehaus.breakBlock.endTime)
                )
        default:
            return 0
        }
    }
}

#Preview("8 am") {
    ClippedTimeline(at: TimeOfDay(8, 0)) {
        sampleTimeline()
    }
}

#Preview("9 am") {
    ClippedTimeline(at: TimeOfDay(9, 0)) {
        sampleTimeline()
    }
}

#Preview("11 am") {
    ClippedTimeline(at: TimeOfDay(11, 0)) {
        sampleTimeline()
    }
}

#Preview("12 pm") {
    ClippedTimeline(at: TimeOfDay(12, 0)) {
        sampleTimeline()
    }
}

#Preview("2 pm") {
    ClippedTimeline(at: TimeOfDay(14, 0)) {
        sampleTimeline()
    }
}

#Preview("4 pm") {
    ClippedTimeline(at: TimeOfDay(16, 0)) {
        sampleTimeline()
    }
}

#Preview("5 pm") {
    ClippedTimeline(at: TimeOfDay(17, 0)) {
        sampleTimeline()
    }
}

#Preview("6:30 pm") {
    ClippedTimeline(at: TimeOfDay(18, 30)) {
        sampleTimeline()
    }
}

#Preview("8 pm") {
    ClippedTimeline(at: TimeOfDay(20, 0)) {
        sampleTimeline()
    }
}

#Preview("11 pm") {
    ClippedTimeline(at: TimeOfDay(23, 0)) {
        sampleTimeline()
    }
}
