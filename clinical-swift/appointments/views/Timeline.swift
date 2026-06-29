import SwiftUI

struct Timeline: View {
    let appointments: [Appointment]
    let scale: TimelineScale

    /// Properties for rendering the "Now" marker line.
    let showsNowMarker: Bool
    var previewNowMarker: Date? = nil
    var appointmentInteractionsEnabled = true
    var onSelectAppointment: (Appointment) -> Void = { _ in }

    static let metrics = TimelineMetrics(
        hourHeight: 60,
        timeColumnWidth: 40,
        verticalPadding: 8,
        horizontalCardMargin: 12,
        verticalCardMargin: 0,
        overlapColumnSpacing: 0,
        compactBreakHeight: 32
    )

    var body: some View {
        if let previewNowMarker {
            timelineContent(now: previewNowMarker)
        } else if showsNowMarker {
            // Update every 1 minute.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                timelineContent(now: context.date)
            }
        } else {
            timelineContent(now: nil)
        }
    }

    private func timelineContent(now: Date?) -> some View {
        GeometryReader { geometry in
            let engine = TimelineLayoutEngine(
                availableWidth: geometry.size.width,
                scale: scale
            )
            let layouts = engine.layout(appointments: appointments)

            ZStack(alignment: .topLeading) {
                TimelineBreakView(
                    scale: scale,
                    availableWidth: geometry.size.width
                )

                TimelineHourGrid(
                    scale: scale,
                    availableWidth: geometry.size.width
                )

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

                if let nowY = nowY(for: now) {
                    NowMarkerView(availableWidth: geometry.size.width)
                        .position(x: geometry.size.width / 2, y: nowY)
                }
            }
        }
        .frame(height: scale.totalHeight)
        .padding(.vertical, Timeline.metrics.verticalPadding)
    }

    private func nowY(for now: Date?) -> CGFloat? {
        guard let now else {
            return nil
        }

        let time = now.timeOfDay
        guard scale.showsTime(time) else {
            return nil
        }

        return scale.yOffset(for: time)
    }
}

func sampleTimeline(appointments: [Appointment] = sampleAppointments) -> some View {
    let scale = TimelineScale(appointments: appointments)

    return Timeline(
        appointments: appointments,
        scale: scale,
        showsNowMarker: true,
        previewNowMarker: Date.now.setTime(9, 30)
    )
    .background(Color("AppBackground"))
}

#Preview {
    sampleTimeline()
}

#Preview("Expanded break") {
    sampleTimeline(
        appointments: sampleAppointments + [
            Appointment(
                patientName: "Draft appointment",
                start: Date.now.setTime(14, 0),
                durationMinutes: 45,
                status: .draft
            )
        ]
    )
}
