import SwiftUI

struct TimelineSegment: View {
    let start: TimeOfDay
    let end: TimeOfDay
    let appointments: [Appointment]
    let metrics: TimelineMetrics
    let now: Date?
    let appointmentInteractionsEnabled: Bool
    let onSelectAppointment: (Appointment) -> Void

    var body: some View {
        GeometryReader { geo in
            let engine = TimelineLayoutEngine(
                metrics: metrics,
                availableWidth: geo.size.width,
                start: start
            )

            let layouts = engine.layout(appointments: appointments)

            ZStack(alignment: .topLeading) {
                /// Hour labels and marker lines
                hourGrid(availableWidth: geo.size.width)

                /// Appointments
                ForEach(layouts) { layout in
                    Button {
                        onSelectAppointment(layout.appointment)
                    } label: {
                        AppointmentCard(appt: layout.appointment)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(appointmentInteractionsEnabled)
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
        (start...end).px
    }

    private var hourMarkers: [Int] {
        guard start.minute == 0 else {
            return []
        }
        guard start < end else {
            return []
        }
        return Array(start.hour...end.hour)
    }

    private var nowY: CGFloat? {
        guard let now else {
            return nil
        }

        let nowTime = TimeOfDay(date: now)
        guard (start..<end).contains(nowTime) else {
            return nil
        }

        return (start...nowTime).px
    }

    private func hourY(for hour: Int) -> CGFloat {
        return (start...TimeOfDay(hour, 0)).px
    }
}
