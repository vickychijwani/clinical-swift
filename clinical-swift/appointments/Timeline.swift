import SwiftUI

struct Timeline: View {
    let appointments: [Appointment]

    static let metrics = TimelineMetrics(
        hourHeight: 72,
        timeColumnWidth: 40,
        topPadding: 20,
        horizontalMargin: 12,
        verticalMargin: 2
    )

    var body: some View {
        ScrollView {
            GeometryReader { geo in
                let engine =
                    TimelineLayoutEngine(
                        metrics: Timeline.metrics,
                        availableWidth: geo.size.width
                    )

                let layouts = engine.layout(
                    appointments: appointments
                )

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
                .padding(.top, Timeline.metrics.topPadding)
            }
            .frame(height: totalHeight)
        }
        .background(Color("AppBackground"))
    }

    func hourGrid(availableWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<13) { hourIndex in
                let y =
                    CGFloat(hourIndex)
                    * Timeline.metrics.hourHeight

                Rectangle()
                    .fill(.gray.opacity(0.15))
                    .frame(height: 1)
                    .position(
                        x: Timeline.metrics.horizontalMargin
                            + Timeline.metrics.timeColumnWidth
                            + availableWidth / 2,
                        y: y
                    )

                // TODO: The hour texts are not exactly right-aligned
                Text(hourText(for: hourIndex + Bitehaus.startTime.hour))
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .position(x: Timeline.metrics.timeColumnWidth - 8, y: y)
            }
        }
    }

    func hourText(for hour: Int) -> String {
        switch hour {
        case 12:
            return "NOON"
        case 13:
            return "1 PM"
        case 14:
            return "2 PM"
        default:
            if hour < 12 {
                return "\(hour) AM"
            } else {
                return "\(hour - 12) PM"
            }
        }
    }

    var totalHeight: CGFloat {
        Timeline.metrics.hourHeight * 12 + Timeline.metrics.topPadding
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
    Timeline(appointments: sampleAppointments)
}
