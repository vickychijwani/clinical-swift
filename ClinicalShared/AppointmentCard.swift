import SwiftUI

struct AppointmentCard: View {
    let appt: Appointment

    var body: some View {
        ScheduleCard(start: appt.start, label: appt.patientName, appearance: appearance)
            .animation(.easeInOut(duration: 0.2), value: appt.status)
    }

    private var appearance: ScheduleCard.Appearance {
        let systemImage = AppointmentStatusPresentation(status: appt.status).systemImage
        return switch appt.status {
        case .draft:
            ScheduleCard.Appearance(
                systemImage: systemImage,
                background: Color.accentColor.opacity(0.08),
                border: Color.accentColor.opacity(0.5),
                borderStyle: StrokeStyle(
                    lineWidth: 3,
                    lineCap: .round,
                    dash: [5, 10]
                ),
                contentOpacity: 1
            )

        case .scheduled:
            ScheduleCard.Appearance(
                systemImage: systemImage,
                background: .white,
                border: .gray.opacity(0.15),
                borderStyle: StrokeStyle(lineWidth: 2),
                contentOpacity: 1
            )

        case .completed:
            ScheduleCard.Appearance(
                systemImage: systemImage,
                background: Color(red: 0.95, green: 0.95, blue: 0.95),
                border: .gray.opacity(0.1),
                borderStyle: StrokeStyle(lineWidth: 2),
                contentOpacity: 0.6
            )

        case .cancelled:
            ScheduleCard.Appearance(
                systemImage: systemImage,
                background: .clear,
                border: .clear,
                borderStyle: StrokeStyle(lineWidth: 0),
                contentOpacity: 0
            )
        }
    }
}

#if !WIDGET_EXTENSION
    func AppointmentCardPreview(
        durationMinutes: Int,
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
            .frame(height: CGFloat(durationMinutes))
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
#endif
