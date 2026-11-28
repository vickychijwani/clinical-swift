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
    let visibleOpening: TimeOfDay
    let visibleClosing: TimeOfDay

    init(
        items: [TimelineItem],
        breakPresentation: BreakPresentation? = nil,
        metrics: TimelineMetrics = .standard,
        visibleOpening: TimeOfDay = Bitehaus.opening,
        visibleClosing: TimeOfDay = Bitehaus.closing
    ) {
        self.metrics = metrics
        self.visibleOpening = visibleOpening
        self.visibleClosing = visibleClosing
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

    /// Builds a scale that fits the day into a fixed widget height without scrolling.
    /// Expanded breaks trim empty outer hours (9–10 AM and 8–9 PM) to preserve short-card height.
    static func widget(
        items: [TimelineItem],
        now: Date?,
        availableHeight: CGFloat
    ) -> TimelineScale {
        let verticalPadding: CGFloat = 6
        let compactBreakHeight: CGFloat = 20
        let breakPresentation: BreakPresentation =
            items.contains { item in
                (Bitehaus.break.start..<Bitehaus.break.end).contains(item.start.timeOfDay)
            } ? .expanded : .compact

        let trimmedOpening = Bitehaus.preferredFirstShiftStart
        let trimmedClosing = TimeOfDay(20, 0)
        let nowTime = now?.timeOfDay

        let visibleOpening: TimeOfDay
        let visibleClosing: TimeOfDay
        switch breakPresentation {
        case .compact:
            visibleOpening = Bitehaus.opening
            visibleClosing = Bitehaus.closing
        case .expanded:
            let needsOpeningHour =
                items.contains { $0.start.timeOfDay < trimmedOpening }
                || (nowTime.map { (Bitehaus.opening..<trimmedOpening).contains($0) } ?? false)
            let needsClosingHour =
                items.contains {
                    $0.start.timeOfDay.totalMinutes + $0.durationMinutes
                        > trimmedClosing.totalMinutes
                }
                || (nowTime.map { (trimmedClosing..<Bitehaus.closing).contains($0) } ?? false)
            visibleOpening = needsOpeningHour ? Bitehaus.opening : trimmedOpening
            visibleClosing = needsClosingHour ? Bitehaus.closing : trimmedClosing
        }

        let usableHeight = max(availableHeight - verticalPadding * 2, 1)
        let hourHeight: CGFloat
        switch breakPresentation {
        case .compact:
            let workingMinutes =
                Bitehaus.break.start.minutes(since: visibleOpening)
                + visibleClosing.minutes(since: Bitehaus.break.end)
            hourHeight = max(
                (usableHeight - compactBreakHeight) / (CGFloat(workingMinutes) / 60),
                1
            )
        case .expanded:
            let visibleMinutes = visibleClosing.minutes(since: visibleOpening)
            hourHeight = max(usableHeight / (CGFloat(visibleMinutes) / 60), 1)
        }

        let metrics = TimelineMetrics(
            hourHeight: hourHeight,
            // Size the time column tightly so two-digit hour labels align with the widget header's leading edge.
            timeColumnWidth: 23,
            verticalPadding: verticalPadding,
            horizontalCardMargin: 6,
            verticalCardMargin: 0,
            overlapColumnSpacing: 0,
            compactBreakHeight: compactBreakHeight
        )
        return TimelineScale(
            items: items,
            breakPresentation: breakPresentation,
            metrics: metrics,
            visibleOpening: visibleOpening,
            visibleClosing: visibleClosing
        )
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
        yOffset(for: visibleClosing)
    }

    var hourMarkers: [TimeOfDay] {
        (visibleOpening.hour...visibleClosing.hour)
            .map { TimeOfDay($0, 0) }
            .filter { time in
                isBreakExpanded
                    || time <= Bitehaus.break.start
                    || time >= Bitehaus.break.end
            }
    }

    /// Content coordinate excluding Timeline's outer vertical padding.
    func yOffset(for proposedTime: TimeOfDay) -> CGFloat {
        let time = min(max(proposedTime, visibleOpening), visibleClosing)
        let firstSegmentHeight = metrics.height(
            for: Bitehaus.break.start.minutes(since: visibleOpening))

        if time <= Bitehaus.break.start {
            return metrics.height(for: time.minutes(since: visibleOpening))
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
                CGFloat(Bitehaus.break.start.minutes(since: visibleOpening))
                + (y - breakY) / breakHeight
                * CGFloat(Bitehaus.break.end.minutes(since: Bitehaus.break.start))
        } else {
            minutes =
                CGFloat(Bitehaus.break.end.minutes(since: visibleOpening))
                + (y - breakY - breakHeight) / metrics.hourHeight * 60
        }
        return visibleOpening + Int(minutes.rounded())
    }

    /// Compact breaks map minutes proportionally, so times inside the break stay visible.
    func showsTime(_ time: TimeOfDay) -> Bool {
        (visibleOpening..<visibleClosing).contains(time)
    }
}
