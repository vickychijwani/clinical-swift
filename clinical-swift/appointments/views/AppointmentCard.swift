import SwiftUI

struct AppointmentCard: View {
    let appt: Appointment

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(style.background)

            cardContent
                .padding(.horizontal, 8)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .clipped()
                .opacity(style.contentOpacity)

            RoundedRectangle(cornerRadius: 8)
                .stroke(style.stroke, style: style.strokeStyle)
        }
        .clipShape(.rect(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.2), value: appt.status)
    }

    private var cardContent: some View {
        ViewThatFits(in: .vertical) {
            // Preferred: vertical layout when there's enough height
            VStack(alignment: .leading, spacing: 2) {
                // Fixed top padding (clearance from card edge)
                Color.clear.frame(height: 4)
                timeText
                patientNameText
                // Fill the rest of the space provided by the layout engine
                Spacer(minLength: 0)
            }

            // Fallback vertical layout with slightly less spacing
            VStack(alignment: .leading) {
                // Fill the rest of the space provided by the layout engine
                Spacer(minLength: 0)
                timeText
                patientNameText
                // Fill the rest of the space provided by the layout engine
                Spacer(minLength: 0)
            }
            .padding(0)

            // Fallback: horizontal layout when vertical doesn't fit
            VStack {
                // Spacers above and below - center HStack vertically
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    timeText
                    patientNameText
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var timeText: some View {
        Text("\(appt.start.formatted(.dateTime.hour().minute()))")
            .styleAppointmentTime()
            .layoutPriority(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var patientNameText: some View {
        ZStack(alignment: .leading) {
            Text(appt.patientName)
                .styleBodyBold()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var style: Style {
        switch appt.status {
        case .draft:
            Style(
                background: Color("AccentColor").opacity(0.08),
                stroke: Color("AccentColor").opacity(0.5),
                strokeStyle: StrokeStyle(
                    lineWidth: 3,
                    lineCap: .round,
                    dash: [5, 10]
                ),
                contentOpacity: 1
            )

        case .scheduled:
            Style(
                background: .white,
                stroke: .gray.opacity(0.15),
                strokeStyle: StrokeStyle(lineWidth: 2),
                contentOpacity: 1
            )

        case .completed:
            Style(
                background: Color(red: 0.95, green: 0.95, blue: 0.95),
                stroke: .gray.opacity(0.1),
                strokeStyle: StrokeStyle(lineWidth: 2),
                contentOpacity: 0.6
            )

        case .cancelled:
            // Normal appointment queries exclude cancelled records before rendering.
            Style(
                background: .clear,
                stroke: .clear,
                strokeStyle: StrokeStyle(lineWidth: 0),
                contentOpacity: 0
            )
        }
    }

    private struct Style {
        let background: Color
        let stroke: Color
        let strokeStyle: StrokeStyle
        let contentOpacity: Double
    }
}

/// Previews of various appointment durations
func AppointmentCardPreview(
    durationMinutes: Minutes,
    status: Appointment.Status = .scheduled
) -> some View {
    VStack(alignment: .leading) {
        Text("\(durationMinutes) mins")
            .font(.title3)
        AppointmentCard(
            appt: .init(
                patientName: "Patient Name",
                start: Date.now.setTime(9, 0),
                durationMinutes: durationMinutes,
                status: status
            )
        )
        .frame(height: durationMinutes.px)
        Color.clear.frame(height: 8)
    }
    .padding(.horizontal, 16)
    .background(Color("AppBackground"))
}

#Preview(traits: .sizeThatFitsLayout) {
    AppointmentCardPreview(durationMinutes: 60)
    AppointmentCardPreview(durationMinutes: 45, status: .draft)
    AppointmentCardPreview(durationMinutes: 40)
    AppointmentCardPreview(durationMinutes: 30)
    AppointmentCardPreview(durationMinutes: 20)
    AppointmentCardPreview(durationMinutes: 15)
    AppointmentCardPreview(durationMinutes: 10)
}
