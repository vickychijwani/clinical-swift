import SwiftUI

struct TimelineSegment: View {
    let timelineStartTime: TimeOfDay
    let timelineEndTime: TimeOfDay
    let appointments: [Appointment]
    let metrics: TimelineMetrics
    let now: Date?

    var body: some View {
        GeometryReader { geo in
            let engine = TimelineLayoutEngine(
                metrics: metrics,
                availableWidth: geo.size.width,
                timelineStartTime: timelineStartTime
            )

            let layouts = engine.layout(appointments: appointments)

            ZStack(alignment: .topLeading) {
                /// Hour labels and marker lines
                hourGrid(availableWidth: geo.size.width)

                /// Appointments
                ForEach(layouts) { layout in
                    AppointmentCard(appt: layout.appointment)
                        .frame(
                            width: layout.rect.width,
                            height: layout.rect.height,
                            alignment: .topLeading
                        )
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.gray.opacity(0.15))
                        )
                        .position(x: layout.rect.midX, y: layout.rect.midY)
                }

                /// Now marker overlays appointment cards
                if let nowY {
                    NowMarkerView(
                        metrics: metrics,
                        availableWidth: geo.size.width
                    )
                    .position(x: geo.size.width / 2, y: nowY)
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
                        x: metrics.horizontalCardMargin
                            + metrics.timeColumnWidth
                            + availableWidth / 2,
                        y: y
                    )

                Text(TimeOfDay(hour, 0).formatted(.hourOnly))
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .position(x: metrics.timeColumnWidth - 8, y: y)
            }
        }
    }

    private var segmentHeight: CGFloat {
        (timelineStartTime...timelineEndTime).px
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

    private var nowY: CGFloat? {
        guard let now else {
            return nil
        }

        let nowTime = TimeOfDay(date: now)
        guard (timelineStartTime..<timelineEndTime).contains(nowTime) else {
            return nil
        }

        return (timelineStartTime...nowTime).px
    }

    private func hourY(for hour: Int) -> CGFloat {
        return (timelineStartTime...TimeOfDay(hour, 0)).px
    }
}
