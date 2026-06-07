import SwiftUI

struct TimelineSegment: View {
    let timelineStartTime: TimeOfDay
    let timelineEndTime: TimeOfDay
    let appointments: [Appointment]
    let metrics: TimelineMetrics

    var body: some View {
        GeometryReader { geo in
            let engine = TimelineLayoutEngine(
                metrics: metrics,
                availableWidth: geo.size.width,
                timelineStartTime: timelineStartTime
            )

            let layouts = engine.layout(appointments: appointments)

            ZStack(alignment: .topLeading) {
                hourGrid(availableWidth: geo.size.width)

                ForEach(layouts) { layout in
                    AppointmentCard(appt: layout.appointment)
                        .frame(
                            width: layout.rect.width,
                            height: layout.rect.height
                        )
                        .position(x: layout.rect.midX, y: layout.rect.midY)
                }
            }
        }
        .frame(height: segmentHeight)
    }

    private func hourGrid(availableWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(hourMarkers, id: \.self) { hour in
                let y = hourY(for: hour)

                Rectangle()
                    .fill(.gray.opacity(0.15))
                    .frame(height: 1)
                    .position(
                        x: metrics.horizontalMargin
                            + metrics.timeColumnWidth
                            + availableWidth / 2,
                        y: y
                    )

                Text(TimeOfDay.init(hour, 0).formatted(.hourOnly))
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .position(x: metrics.timeColumnWidth - 8, y: y)
            }
        }
    }

    private var segmentHeight: CGFloat {
        CGFloat(timelineEndTime.minutes(since: timelineStartTime))
            * metrics.pixelsPerMinute
    }

    private var hourMarkers: [Int] {
        guard timelineStartTime.minute == 0 else {
            return []
        }
        guard timelineStartTime < timelineEndTime else {
            return []
        }
        return Array(timelineStartTime.hour...timelineEndTime.hour)
    }

    private func hourY(for hour: Int) -> CGFloat {
        let markerHour = TimeOfDay.init(hour, 0)
        return CGFloat(markerHour.minutes(since: timelineStartTime))
            * metrics.pixelsPerMinute
    }
}
