import ClinicalModels
import CoreGraphics
import Foundation

struct TimelineMetrics: Equatable, Sendable {
    static let standard = TimelineMetrics(
        hourHeight: 60,
        timeColumnWidth: 40,
        verticalPadding: 8,
        horizontalCardMargin: 12,
        verticalCardMargin: 0,
        overlapColumnSpacing: 0,
        compactBreakHeight: 32
    )

    /// Height of 1 hour in pixels
    let hourHeight: CGFloat

    /// Width of time labels in left column of timeline
    let timeColumnWidth: CGFloat

    /// Padding above timeline
    let verticalPadding: CGFloat

    /// Margin left/right of appointment card, relative to hour marker lines
    let horizontalCardMargin: CGFloat

    /// Margin above/below an appointment card, to separate edges clearly from hour markers
    let verticalCardMargin: CGFloat

    /// Horizontal spacing between appointments that overlap in time
    let overlapColumnSpacing: CGFloat

    /// Height used to represent the clinic break when it is compact
    let compactBreakHeight: CGFloat

    var contentLeadingInset: CGFloat {
        timeColumnWidth + horizontalCardMargin + 4
    }

    func contentWidth(availableWidth: CGFloat) -> CGFloat {
        max(
            availableWidth
                - timeColumnWidth
                - horizontalCardMargin * 2, 0)
    }

    /// Number of vertical pixels representing 1 minute
    private var pixelsPerMinute: CGFloat {
        hourHeight / 60
    }

    func height(for minutes: Minutes) -> CGFloat {
        CGFloat(minutes) * pixelsPerMinute
    }

    func height(for range: Range<TimeOfDay>) -> CGFloat {
        height(for: range.minutes)
    }

    func height(for range: ClosedRange<TimeOfDay>) -> CGFloat {
        height(for: range.minutes)
    }
}

struct TimelineScale {
    enum BreakPresentation {
        case compact
        case expanded
    }

    let breakPresentation: BreakPresentation
    let metrics: TimelineMetrics

    init(
        items: [TimelineItem],
        breakPresentation: BreakPresentation? = nil,
        metrics: TimelineMetrics = .standard
    ) {
        self.metrics = metrics
        if let breakPresentation {
            self.breakPresentation = breakPresentation
            return
        }
        self.breakPresentation =
            items.contains { item in
                (Bitehaus.break.start..<Bitehaus.break.end).contains(
                    item.start.timeOfDay
                )
            } ? .expanded : .compact
    }

    var isBreakExpanded: Bool {
        breakPresentation == .expanded
    }

    var breakHeight: CGFloat {
        switch breakPresentation {
        case .compact:
            metrics.compactBreakHeight
        case .expanded:
            metrics.height(for: Bitehaus.break.start..<Bitehaus.break.end)
        }
    }

    var totalHeight: CGFloat {
        yOffset(for: Bitehaus.closing)
    }

    var hourMarkers: [TimeOfDay] {
        (Bitehaus.opening.hour...Bitehaus.closing.hour)
            .map { TimeOfDay($0, 0) }
            .filter { time in
                isBreakExpanded
                    || time <= Bitehaus.break.start
                    || time >= Bitehaus.break.end
            }
    }

    /// Content coordinate excluding Timeline's outer vertical padding.
    func yOffset(for proposedTime: TimeOfDay) -> CGFloat {
        let time = min(max(proposedTime, Bitehaus.opening), Bitehaus.closing)
        let firstSegmentHeight = metrics.height(
            for: Bitehaus.break.start.minutes(since: Bitehaus.opening))

        if time <= Bitehaus.break.start {
            return metrics.height(for: time.minutes(since: Bitehaus.opening))
        }

        if time < Bitehaus.break.end {
            let elapsedBreakMinutes = time.minutes(since: Bitehaus.break.start)
            let breakDurationMinutes = Bitehaus.break.end.minutes(since: Bitehaus.break.start)
            let breakProgress = CGFloat(elapsedBreakMinutes) / CGFloat(breakDurationMinutes)

            return firstSegmentHeight + breakHeight * breakProgress
        }

        return firstSegmentHeight
            + breakHeight
            + metrics.height(for: time.minutes(since: Bitehaus.break.end))
    }

    func height(from start: TimeOfDay, to end: TimeOfDay) -> CGFloat {
        max(yOffset(for: end) - yOffset(for: start), 0)
    }

    /// Invert the same piecewise scale used to draw cards, including compact break minutes.
    func time(at proposedY: CGFloat) -> TimeOfDay {
        let y = min(max(proposedY, 0), totalHeight)
        let breakY = yOffset(for: Bitehaus.break.start)
        let minutes: CGFloat
        if y <= breakY {
            minutes = y / metrics.hourHeight * 60
        } else if y < breakY + breakHeight {
            minutes =
                CGFloat(Bitehaus.break.start.minutes(since: Bitehaus.opening))
                + (y - breakY) / breakHeight
                * CGFloat(Bitehaus.break.end.minutes(since: Bitehaus.break.start))
        } else {
            minutes =
                CGFloat(Bitehaus.break.end.minutes(since: Bitehaus.opening))
                + (y - breakY - breakHeight) / metrics.hourHeight * 60
        }
        return Bitehaus.opening + Int(minutes.rounded())
    }

    func showsTime(_ time: TimeOfDay) -> Bool {
        guard (Bitehaus.opening..<Bitehaus.closing).contains(time) else {
            return false
        }

        return isBreakExpanded
            || !(Bitehaus.break.start..<Bitehaus.break.end).contains(time)
    }
}
