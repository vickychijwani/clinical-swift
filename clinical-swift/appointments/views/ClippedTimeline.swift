import SwiftUI

struct ClippedTimeline<Content: View>: View {
    let timeline: Content
    let center: TimeOfDay
    let clippedHeight: CGFloat

    init(at center: TimeOfDay, height: CGFloat = 240, @ViewBuilder timeline: () -> Content) {
        self.timeline = timeline()
        self.center = center
        self.clippedHeight = height
    }

    var body: some View {
        let yOffset = yOffsetForCenter.clamp(to: 0...yOffsetForClosingTime)
        ClippedView(height: clippedHeight, yOffset: yOffset) {
            timeline
        }
        .animation(.easeInOut(duration: 0.2), value: yOffset)
        .allowsHitTesting(false)
    }

    private var yOffsetForCenter: CGFloat {
        return
            // Align `center` to top of clipped timeline
            yOffsetFor(center)
            // Move the `center` down to center of clipped timeline
            - clippedHeight / 2
    }

    private var yOffsetForClosingTime: CGFloat {
        return
            // Align `closing` to top of clipped timeline
            yOffsetFor(Bitehaus.closing)
            // Move Timeline up by 2x padding to align *bottom edge* of Timeline
            // to top of clipped timeline
            + Timeline.metrics.verticalPadding * 2
            // Move it down by clipped height to align to bottom edge of clipped timeline
            - clippedHeight
    }

    private func yOffsetFor(_ time: TimeOfDay) -> CGFloat {
        switch time {
        case .midnight..<Bitehaus.opening:
            return 0
        case Bitehaus.opening..<Bitehaus.break.start:
            return (Bitehaus.opening...time).px
        case Bitehaus.break.start..<Bitehaus.break.end:
            return Bitehaus.firstHalf.px
        case Bitehaus.break.end...TimeOfDay(23, 59):
            return Bitehaus.firstHalf.px + TimelineBreakView.height
                + (Bitehaus.break.end...time).px
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

#Preview("9 pm") {
    ClippedTimeline(at: TimeOfDay(21, 0)) {
        sampleTimeline()
    }
}

#Preview("11 pm") {
    ClippedTimeline(at: TimeOfDay(23, 0)) {
        sampleTimeline()
    }
}
