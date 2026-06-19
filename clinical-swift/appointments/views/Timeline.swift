import SwiftUI
 
struct Timeline: View {
    let appointments: [Appointment]
    let startTime: TimeOfDay
    let endTime: TimeOfDay
    let breakBlock: BreakBlock

    /// Properties for rendering the "Now" marker line.
    let showsNowMarker: Bool
    var previewNowMarker: Date? = nil

    static let metrics = TimelineMetrics(
        hourHeight: 60,
        timeColumnWidth: 40,
        verticalPadding: 8,
        horizontalCardMargin: 12,
        verticalCardMargin: 0,
        overlapColumnSpacing: 0
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
                timelineStartTime: startTime,
                timelineEndTime: breakBlock.start,
                appointments: appointmentsBeforeBreak,
                metrics: Timeline.metrics,
                now: now
            )

            TimelineBreakView(
                block: breakBlock,
                metrics: Timeline.metrics
            )

            TimelineSegment(
                timelineStartTime: breakBlock.end,
                timelineEndTime: endTime,
                appointments: appointmentsAfterBreak,
                metrics: Timeline.metrics,
                now: now
            )
        }
        .padding(.vertical, Timeline.metrics.verticalPadding)
    }

    private var appointmentsBeforeBreak: [Appointment] {
        appointments.filter { $0.startTime.timeOfDay < breakBlock.start }
    }

    private var appointmentsAfterBreak: [Appointment] {
        appointments.filter { $0.startTime.timeOfDay >= breakBlock.end }
    }
}

func sampleTimeline() -> some View {
    return Timeline(
        appointments: sampleAppointments,
        startTime: Bitehaus.opening,
        endTime: Bitehaus.closing,
        breakBlock: Bitehaus.break,
        showsNowMarker: true,
        previewNowMarker: Date.now.setTime(9, 30)
    )
    .background(Color("AppBackground"))
}

#Preview {
    sampleTimeline()
}
