import SwiftUI

struct Timeline: View {
    let appointments: [Appointment]

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
        overlapColumnSpacing: 0
    )

    static let scheduleScale = TimelineScale()

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
                start: Bitehaus.opening,
                end: Bitehaus.break.start,
                appointments: appointmentsBeforeBreak,
                now: now,
                appointmentInteractionsEnabled: appointmentInteractionsEnabled,
                onSelectAppointment: onSelectAppointment
            )

            TimelineBreakView()

            TimelineSegment(
                start: Bitehaus.break.end,
                end: Bitehaus.closing,
                appointments: appointmentsAfterBreak,
                now: now,
                appointmentInteractionsEnabled: appointmentInteractionsEnabled,
                onSelectAppointment: onSelectAppointment
            )
        }
        .padding(.vertical, Timeline.metrics.verticalPadding)
    }

    private var appointmentsBeforeBreak: [Appointment] {
        appointments.filter { $0.start.timeOfDay < Bitehaus.break.start }
    }

    private var appointmentsAfterBreak: [Appointment] {
        appointments.filter { $0.start.timeOfDay >= Bitehaus.break.end }
    }
}

func sampleTimeline() -> some View {
    return Timeline(
        appointments: sampleAppointments,
        showsNowMarker: true,
        previewNowMarker: Date.now.setTime(9, 30)
    )
    .background(Color("AppBackground"))
}

#Preview {
    sampleTimeline()
}
