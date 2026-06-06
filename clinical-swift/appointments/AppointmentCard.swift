import SwiftUI

struct AppointmentCard: View {
    let appt: Appointment

    var body: some View {
        ViewThatFits(in: .vertical) {
            // Preferred: vertical layout when there's enough height
            VStack(alignment: .leading, spacing: 4) {
                // Fixed top padding (clearance from card edge)
                Color.clear.frame(height: 8)
                Text(timeText)
                    .font(.caption.monospacedDigit())
                Text(appt.patientName)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                // Fill the rest of the space provided by the layout engine
                Spacer(minLength: 0)
            }

            // Fallback: horizontal layout when vertical doesn't fit
            VStack {
                // Spacers above and below - center HStack vertically
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(timeText)
                        .font(.caption.monospacedDigit())
                    Text(appt.patientName)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.gray.opacity(0.15))
        )
    }

    var timeText: String {
        return "\(appt.startTime.formatted(.dateTime.hour().minute()))"
    }
}

/// Previews of various appointment durations
func AppointmentCardPreview(durationMinutes: Int) -> some View {
    VStack(alignment: .leading) {
        Text("\(durationMinutes) mins")
            .font(.title3)
        AppointmentCard(appt: .init(
            patientName: "Patient Name",
            startTime: Date.now.setTime(9, 0),
            durationMinutes: durationMinutes,
            status: .scheduled
        ))
        .frame(height: CGFloat(durationMinutes) * Timeline.metrics.pixelsPerMinute)
        Color.clear.frame(height: 8)
    }
    .padding(.horizontal, 16)
    .background(Color("AppBackground"))
}

#Preview(traits: .sizeThatFitsLayout) {
    AppointmentCardPreview(durationMinutes: 60)
    AppointmentCardPreview(durationMinutes: 45)
    AppointmentCardPreview(durationMinutes: 40)
    AppointmentCardPreview(durationMinutes: 30)
    AppointmentCardPreview(durationMinutes: 20)
    AppointmentCardPreview(durationMinutes: 15)
    AppointmentCardPreview(durationMinutes: 10)
}
