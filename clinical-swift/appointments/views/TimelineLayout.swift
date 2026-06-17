/// Layout Engine for Timeline view
/// Must remain independent of SwiftUI

import Foundation
import CoreGraphics

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

    /// Number of vertical pixels representing 1 minute
    var pixelsPerMinute: CGFloat {
        hourHeight / 60
    }

    var contentLeadingInset: CGFloat {
        timeColumnWidth + horizontalCardMargin + 4
    }

    func contentWidth(availableWidth: CGFloat) -> CGFloat {
        availableWidth
            - timeColumnWidth
            - horizontalCardMargin * 2
    }
}

struct TimelineLayoutEngine {
    let metrics: TimelineMetrics
    let availableWidth: CGFloat
    let timelineStartTime: TimeOfDay

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
        metrics.contentWidth(availableWidth: availableWidth)
    }

    private func cardWidth(columnCount: Int) -> CGFloat {
        guard columnCount > 1 else {
            return cardWidth
        }

        let spacing = metrics.overlapColumnSpacing * CGFloat(columnCount - 1)
        return max((cardWidth - spacing) / CGFloat(columnCount), 0)
    }

    private func cardHeight(for appt: Appointment) -> CGFloat {
        return CGFloat(appt.durationMinutes) * metrics.pixelsPerMinute
            // 2x to account for top and bottom clearance both
            - metrics.verticalCardMargin * 2
    }

    private func cardX(column: Int, columnWidth: CGFloat) -> CGFloat {
        metrics.contentLeadingInset
            + CGFloat(column) * (columnWidth + metrics.overlapColumnSpacing)
    }

    private func cardY(for appt: Appointment) -> CGFloat {
        let minutesFromStart = appt.startTime.minutes(since: timelineStartTime)
        return CGFloat(minutesFromStart) * metrics.pixelsPerMinute
            + metrics.verticalCardMargin
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
               startMinute >= groupEndMinute {
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

            if let reusableColumn = columnEndMinutes.firstIndex(where: { $0 <= startMinute }) {
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
        appointment.startTime.minutes(since: timelineStartTime)
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
