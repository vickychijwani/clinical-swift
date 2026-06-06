/// Layout Engine for Timeline view
/// Must remain independent of SwiftUI

import Foundation

struct TimelineMetrics {
    /// Height of 1 hour in pixels
    let hourHeight: CGFloat

    /// Width of time labels in left column of timeline
    let timeColumnWidth: CGFloat

    /// Padding above timeline
    let topPadding: CGFloat

    /// Margin left/right of appointment card, relative to hour marker lines
    let horizontalMargin: CGFloat

    /// Margin above/below an appointment card, to separate edges clearly from hour markers
    let verticalMargin: CGFloat

    /// Number of vertical pixels representing 1 minute
    var pixelsPerMinute: CGFloat {
        hourHeight / 60
    }
}

struct AppointmentLayoutInfo: Identifiable {
    let id: UUID
    let appointment: Appointment
    let rect: CGRect
}

struct TimelineLayoutEngine {
    let metrics: TimelineMetrics
    let availableWidth: CGFloat

    func layout(
        appointments: [Appointment]
    ) -> [AppointmentLayoutInfo] {
        return appointments.map { appt in
            let rect = CGRect(
                origin: CGPoint(x: cardX, y: cardY(for: appt)),
                size: CGSize(width: cardWidth, height: cardHeight(for: appt))
            )
            return AppointmentLayoutInfo(
                id: appt.id,
                appointment: appt,
                rect: rect
            )
        }
    }

    private var cardWidth: CGFloat {
        availableWidth
            - metrics.timeColumnWidth
            // 2x to account for inset on either side
            - metrics.horizontalMargin * 2
    }

    private func cardHeight(for appt: Appointment) -> CGFloat {
        return CGFloat(appt.durationMinutes) * metrics.pixelsPerMinute
            // 2x to account for top and bottom clearance both
            - metrics.verticalMargin * 2
    }

    private var cardX: CGFloat {
        return metrics.timeColumnWidth + metrics.horizontalMargin
            // Further inset by 4px on left side - can we get rid of this magic constant?
            + 4
    }

    private func cardY(for appt: Appointment) -> CGFloat {
        let minutesFromStart = appt.startTime.minutes(since: Bitehaus.startTime)
        return CGFloat(minutesFromStart) * metrics.pixelsPerMinute
            + metrics.verticalMargin
    }
}
