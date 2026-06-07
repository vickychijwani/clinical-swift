import SwiftUI

struct Timeline: View {
    let appointments: [Appointment]
    let startTime: TimeOfDay
    let endTime: TimeOfDay
    let breakBlock: BreakBlock

    static let metrics = TimelineMetrics(
        hourHeight: 72,
        timeColumnWidth: 40,
        topPadding: 20,
        horizontalMargin: 12,
        verticalMargin: 1
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TimelineSegment(
                    timelineStartTime: startTime,
                    timelineEndTime: breakBlock.startTime,
                    appointments: appointmentsBeforeBreak,
                    metrics: Timeline.metrics
                )

                TimelineBreakView(
                    block: breakBlock,
                    metrics: Timeline.metrics
                )

                TimelineSegment(
                    timelineStartTime: breakBlock.endTime,
                    timelineEndTime: endTime,
                    appointments: appointmentsAfterBreak,
                    metrics: Timeline.metrics
                )
            }
            .padding(.top, Timeline.metrics.topPadding)
        }
        .background(Color("AppBackground"))
    }

    private var appointmentsBeforeBreak: [Appointment] {
        appointments.filter { $0.startTime.timeOfDay < breakBlock.startTime }
    }

    private var appointmentsAfterBreak: [Appointment] {
        appointments.filter { $0.startTime.timeOfDay >= breakBlock.endTime }
    }
}

let sampleAppointments: [Appointment] = [
    .init(
        patientName: "Anjali Desai",
        startTime: Date.now.setTime(9, 0),
        durationMinutes: 60,
        status: .scheduled
    ),
    .init(
        patientName: "Ubaid Khan",
        startTime: Date.now.setTime(12, 0),
        durationMinutes: 15,
        status: .scheduled
    ),
    .init(
        patientName: "Arjun Sethi",
        startTime: Date.now.setTime(12, 15),
        durationMinutes: 15,
        status: .scheduled
    ),
    .init(
        patientName: "Arjun Sethi",
        startTime: Date.now.setTime(12, 30),
        durationMinutes: 30,
        status: .scheduled
    ),
    .init(
        patientName: "Nandini Iyer",
        startTime: Date.now.setTime(20, 0),
        durationMinutes: 60,
        status: .scheduled
    ),
]

#Preview {
    Timeline(
        appointments: sampleAppointments,
        startTime: Bitehaus.startTime,
        endTime: Bitehaus.closingTime,
        breakBlock: Bitehaus.breakBlock
    )
}
