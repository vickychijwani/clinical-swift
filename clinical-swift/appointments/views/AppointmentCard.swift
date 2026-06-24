import SwiftUI

struct AppointmentCard: View {
    let appt: Appointment

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch appt.status {
            case .draft:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color("AccentColor").opacity(0.08).gradient)
            default:
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white)
            }

            cardContent
                .padding(.horizontal, 8)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .clipped()

            switch appt.status {
            case .draft:
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        Color("AccentColor").opacity(0.5),
                        style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round,
                            dash: [5, 10]
                        )
                    )
            default:
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 2)
            }
        }
        .clipShape(.rect(cornerRadius: 8))
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
