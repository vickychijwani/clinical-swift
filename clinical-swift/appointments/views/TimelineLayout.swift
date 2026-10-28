import ClinicalModels
import CoreGraphics
import Foundation

/// Layout Engine for Timeline view
/// Must remain independent of SwiftUI

struct TimelineMetrics {
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
    fileprivate var pixelsPerMinute: CGFloat {
        hourHeight / 60
    }
}

struct TimelineScale {
    enum BreakPresentation {
        case compact
        case expanded
    }

    let breakPresentation: BreakPresentation

    init(items: [TimelineItem], breakPresentation: BreakPresentation? = nil) {
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
            Timeline.metrics.compactBreakHeight
        case .expanded:
            (Bitehaus.break.start..<Bitehaus.break.end).px
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
        let firstSegmentHeight = Bitehaus.break.start.minutes(since: Bitehaus.opening).px

        if time <= Bitehaus.break.start {
            return time.minutes(since: Bitehaus.opening).px
        }

        if time < Bitehaus.break.end {
            let elapsedBreakMinutes = time.minutes(since: Bitehaus.break.start)
            let breakDurationMinutes = Bitehaus.break.end.minutes(since: Bitehaus.break.start)
            let breakProgress = CGFloat(elapsedBreakMinutes) / CGFloat(breakDurationMinutes)

            return firstSegmentHeight + breakHeight * breakProgress
        }

        return firstSegmentHeight
            + breakHeight
            + time.minutes(since: Bitehaus.break.end).px
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
            minutes = y / Timeline.metrics.hourHeight * 60
        } else if y < breakY + breakHeight {
            minutes =
                CGFloat(Bitehaus.break.start.minutes(since: Bitehaus.opening))
                + (y - breakY) / breakHeight
                * CGFloat(Bitehaus.break.end.minutes(since: Bitehaus.break.start))
        } else {
            minutes =
                CGFloat(Bitehaus.break.end.minutes(since: Bitehaus.opening))
                + (y - breakY - breakHeight) / Timeline.metrics.hourHeight * 60
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

struct TimelineLayoutEngine {
    let availableWidth: CGFloat
    let scale: TimelineScale

    func layout(
        items: [TimelineItem], floatingID: TimelineItem.ID? = nil
    ) -> [TimelineItemLayoutInfo] {
        // The held card uses the full content width and does not displace other cards.
        let regular = items.filter { $0.id != floatingID }
        let floating = items.filter { $0.id == floatingID }
        return overlappingGroups(for: regular).flatMap { group in
            layout(group: group)
        } + floating.flatMap { layout(group: [$0]) }
    }

    private func layout(group: [TimelineItem]) -> [TimelineItemLayoutInfo] {
        let assignments = columnAssignments(for: group)
        let columnCount = max(
            assignments.map(\.column).max().map { $0 + 1 } ?? 1,
            1
        )
        let width = cardWidth(columnCount: columnCount)

        return assignments.map { assignment in
            let item = assignment.item
            let rect = CGRect(
                x: cardX(column: assignment.column, columnWidth: width),
                y: cardY(for: item),
                width: width,
                height: cardHeight(for: item)
            )
            return TimelineItemLayoutInfo(
                id: item.id,
                item: item,
                rect: rect
            )
        }
    }

    private var cardWidth: CGFloat {
        Timeline.metrics.contentWidth(availableWidth: availableWidth)
    }

    private func cardWidth(columnCount: Int) -> CGFloat {
        guard columnCount > 1 else {
            return cardWidth
        }

        let spacing = Timeline.metrics.overlapColumnSpacing * CGFloat(columnCount - 1)
        return max((cardWidth - spacing) / CGFloat(columnCount), 0)
    }

    private func cardHeight(for item: TimelineItem) -> CGFloat {
        max(
            scale.height(
                from: item.start.timeOfDay,
                to: item.start.timeOfDay + item.durationMinutes
            )
                // 2x to account for top and bottom clearance both
                - Timeline.metrics.verticalCardMargin * 2,
            0
        )
    }

    private func cardX(column: Int, columnWidth: CGFloat) -> CGFloat {
        Timeline.metrics.contentLeadingInset
            + CGFloat(column) * (columnWidth + Timeline.metrics.overlapColumnSpacing)
    }

    private func cardY(for item: TimelineItem) -> CGFloat {
        return scale.yOffset(for: item.start.timeOfDay)
            + Timeline.metrics.verticalCardMargin
    }

    private func overlappingGroups(
        for items: [TimelineItem]
    ) -> [[TimelineItem]] {
        let sortedItems = items.sorted(by: itemSort)
        var groups: [[TimelineItem]] = []
        var currentGroup: [TimelineItem] = []
        var currentGroupEndMinute: Int?

        for item in sortedItems {
            let startMinute = startMinute(for: item)
            let endMinute = endMinute(for: item)

            if let groupEndMinute = currentGroupEndMinute,
                startMinute >= groupEndMinute
            {
                groups.append(currentGroup)
                currentGroup = [item]
                currentGroupEndMinute = endMinute
            } else {
                currentGroup.append(item)
                currentGroupEndMinute = max(currentGroupEndMinute ?? endMinute, endMinute)
            }
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups
    }

    private func columnAssignments(
        for items: [TimelineItem]
    ) -> [TimelineItemColumnAssignment] {
        var columnEndMinutes: [Int] = []

        return items.map { item in
            let startMinute = startMinute(for: item)
            let endMinute = endMinute(for: item)
            let column: Int

            if let reusableColumn = columnEndMinutes.firstIndex(where: {
                $0 <= startMinute
            }) {
                column = reusableColumn
                columnEndMinutes[reusableColumn] = endMinute
            } else if columnEndMinutes.count < Self.maximumOverlappingColumns {
                column = columnEndMinutes.count
                columnEndMinutes.append(endMinute)
            } else {
                column = Self.maximumOverlappingColumns - 1
                columnEndMinutes[column] = max(columnEndMinutes[column], endMinute)
            }

            return TimelineItemColumnAssignment(
                item: item,
                column: column
            )
        }
    }

    private func itemSort(
        lhs: TimelineItem,
        rhs: TimelineItem
    ) -> Bool {
        let lhsStart = startMinute(for: lhs)
        let rhsStart = startMinute(for: rhs)
        if lhsStart != rhsStart {
            return lhsStart < rhsStart
        }

        let lhsEnd = endMinute(for: lhs)
        let rhsEnd = endMinute(for: rhs)
        if lhsEnd != rhsEnd {
            return lhsEnd < rhsEnd
        }

        return lhs.id.sortKey < rhs.id.sortKey
    }

    private func startMinute(for item: TimelineItem) -> Int {
        item.start.timeOfDay.minutes(since: Bitehaus.opening)
    }

    private func endMinute(for item: TimelineItem) -> Int {
        startMinute(for: item) + item.durationMinutes
    }

    private static let maximumOverlappingColumns = 3
}

struct TimelineItemLayoutInfo: Identifiable {
    let id: TimelineItem.ID
    let item: TimelineItem
    let rect: CGRect
}

private struct TimelineItemColumnAssignment {
    let item: TimelineItem
    let column: Int
}

extension Minutes {
    var px: CGFloat {
        CGFloat(self) * Timeline.metrics.pixelsPerMinute
    }
}

extension ClosedRange where Bound == TimeOfDay {
    var px: CGFloat { self.minutes.px }
}

extension Range where Bound == TimeOfDay {
    var px: CGFloat { self.minutes.px }
}
