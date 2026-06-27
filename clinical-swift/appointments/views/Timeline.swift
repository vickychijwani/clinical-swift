import SwiftUI

struct Timeline: View {
    let appointments: [Appointment]
    let start: TimeOfDay
    let end: TimeOfDay
    let breakBlock: BreakBlock

    /// Properties for rendering the "Now" marker line.
    let showsNowMarker: Bool
    var previewNowMarker: Date? = nil
    var appointmentInteractionsEnabled = true

    static let metrics = TimelineMetrics(
        hourHeight: 60,
        timeColumnWidth: 40,
        verticalPadding: 8,
        horizontalCardMargin: 12,
        verticalCardMargin: 0,
        overlapColumnSpacing: 0
    )

    static let scheduleScale = TimelineScale(
        metrics: metrics,
        start: Bitehaus.opening,
        end: Bitehaus.closing,
        breakBlock: Bitehaus.break,
        breakHeight: TimelineBreakView.height
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
        VStack(spacing: 0) {
            TimelineSegment(
                start: start,
                end: breakBlock.start,
                appointments: appointmentsBeforeBreak,
                metrics: Timeline.metrics,
                now: now,
                appointmentInteractionsEnabled: appointmentInteractionsEnabled
            )

            TimelineBreakView(
                block: breakBlock,
                metrics: Timeline.metrics
            )

            TimelineSegment(
                start: breakBlock.end,
                end: end,
                appointments: appointmentsAfterBreak,
                metrics: Timeline.metrics,
                now: now,
                appointmentInteractionsEnabled: appointmentInteractionsEnabled
            )
        }
        .padding(.vertical, Timeline.metrics.verticalPadding)
    }

    private var appointmentsBeforeBreak: [Appointment] {
        appointments.filter { $0.start.timeOfDay < breakBlock.start }
    }

    private var appointmentsAfterBreak: [Appointment] {
        appointments.filter { $0.start.timeOfDay >= breakBlock.end }
    }
}

func sampleTimeline() -> some View {
    return Timeline(
        appointments: sampleAppointments,
        start: Bitehaus.opening,
        end: Bitehaus.closing,
        breakBlock: Bitehaus.break,
        showsNowMarker: true,
        previewNowMarker: Date.now.setTime(9, 30)
    )
    .background(Color("AppBackground"))
}

#Preview {
    sampleTimeline()
}
