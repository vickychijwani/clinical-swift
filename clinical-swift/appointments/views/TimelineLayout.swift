/// Layout Engine for Timeline view
/// Must remain independent of SwiftUI

import CoreGraphics
import Foundation

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
        availableWidth
            - timeColumnWidth
            - horizontalCardMargin * 2
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

    init(appointments: [Appointment]) {
        breakPresentation =
            appointments.contains { appointment in
                (Bitehaus.break.start..<Bitehaus.break.end).contains(
                    appointment.start.timeOfDay
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
        appointments: [Appointment]
    ) -> [AppointmentLayoutInfo] {
        overlappingGroups(for: appointments).flatMap { group in
            layout(group: group)
        }
    }

    private func layout(group: [Appointment]) -> [AppointmentLayoutInfo] {
        let assignments = columnAssignments(for: group)
        let columnCount = max(
            assignments.map(\.column).max().map { $0 + 1 } ?? 1,
            1
        )
        let width = cardWidth(columnCount: columnCount)

        return assignments.map { assignment in
            let appt = assignment.appointment
            let rect = CGRect(
                x: cardX(column: assignment.column, columnWidth: width),
                y: cardY(for: appt),
                width: width,
                height: cardHeight(for: appt)
            )
            return AppointmentLayoutInfo(
                id: appt.id,
                appointment: appt,
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

    private func cardHeight(for appt: Appointment) -> CGFloat {
        max(
            scale.height(
                from: appt.start.timeOfDay,
                to: appt.start.timeOfDay + appt.durationMinutes
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

    private func cardY(for appt: Appointment) -> CGFloat {
        return scale.yOffset(for: appt.start.timeOfDay)
            + Timeline.metrics.verticalCardMargin
    }

    private func overlappingGroups(
        for appointments: [Appointment]
    ) -> [[Appointment]] {
        let sortedAppointments = appointments.sorted(by: appointmentSort)
        var groups: [[Appointment]] = []
        var currentGroup: [Appointment] = []
        var currentGroupEndMinute: Int?

        for appointment in sortedAppointments {
            let startMinute = startMinute(for: appointment)
            let endMinute = endMinute(for: appointment)

            if let groupEndMinute = currentGroupEndMinute,
                startMinute >= groupEndMinute
            {
                groups.append(currentGroup)
                currentGroup = [appointment]
                currentGroupEndMinute = endMinute
            } else {
                currentGroup.append(appointment)
                currentGroupEndMinute = max(currentGroupEndMinute ?? endMinute, endMinute)
            }
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups
    }

    private func columnAssignments(
        for appointments: [Appointment]
    ) -> [AppointmentColumnAssignment] {
        var columnEndMinutes: [Int] = []

        return appointments.map { appointment in
            let startMinute = startMinute(for: appointment)
            let endMinute = endMinute(for: appointment)
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

            return AppointmentColumnAssignment(
                appointment: appointment,
                column: column
            )
        }
    }

    private func appointmentSort(
        lhs: Appointment,
        rhs: Appointment
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

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func startMinute(for appointment: Appointment) -> Int {
        appointment.start.timeOfDay.minutes(since: Bitehaus.opening)
    }

    private func endMinute(for appointment: Appointment) -> Int {
        startMinute(for: appointment) + appointment.durationMinutes
    }

    private static let maximumOverlappingColumns = 3
}

struct AppointmentLayoutInfo: Identifiable {
    let id: UUID
    let appointment: Appointment
    let rect: CGRect
}

private struct AppointmentColumnAssignment {
    let appointment: Appointment
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
