import ClinicalModels
import SwiftUI

struct AppointmentCard: View {
    @Environment(\.appPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    @Environment(\.scheduleCardStyle) private var cardStyle
    let appt: Appointment
    var isSelected = false
    var isDeemphasized = false
    var contentTrailingInset: CGFloat = 0
    var presentation: ScheduleCardPresentation? = nil

    private static let selectedBorderWidth: CGFloat = 1.5
    private static let lightSelectedBorderOpacity = 0.62
    private static let darkSelectedBorderOpacity = 0.55

    var body: some View {
        ScheduleCard(
            start: appt.start, label: appt.patientName, appearance: appearance,
            isDeemphasized: isDeemphasized,
            contentTrailingInset: contentTrailingInset,
            presentation: presentation
        )
        .animation(.easeInOut(duration: 0.2), value: appt.status)
        .animation(.smooth(duration: 0.2), value: isSelected)
    }

    private var appearance: ScheduleCard.Appearance {
        let systemImage = AppointmentStatusPresentation(status: appt.status).systemImage
        if isSelected, appt.status == .scheduled || appt.status == .completed {
            return selectedAppearance(systemImage: systemImage)
        }
        return switch appt.status {
        case .draft:
            ScheduleCard.Appearance(
                systemImage: systemImage,
                background: .draft,
                border: palette[.activeBorder],
                borderStyle: StrokeStyle(lineWidth: cardStyle.borderWidth)
            )

        case .scheduled:
            ScheduleCard.Appearance(
                systemImage: systemImage,
                background: .color(palette[.card]),
                border: palette[.cardBorder],
                borderStyle: StrokeStyle(lineWidth: cardStyle.borderWidth),
                contentOpacity: 1
            )

        case .completed:
            ScheduleCard.Appearance(
                systemImage: systemImage,
                background: .color(palette[.completedCard]),
                border: palette[.completedBorder],
                borderStyle: StrokeStyle(lineWidth: cardStyle.borderWidth),
                contentOpacity: 0.6
            )

        case .cancelled:
            ScheduleCard.Appearance(
                systemImage: systemImage,
                background: .color(.clear),
                border: .clear,
                borderStyle: StrokeStyle(lineWidth: 0),
                contentOpacity: 0
            )
        }
    }

    private var selectionInk: Color {
        var resolved = Color.primary.resolve(in: environment)
        resolved.opacity = 1
        return Color(resolved)
    }

    private func selectedAppearance(systemImage: String) -> ScheduleCard.Appearance {
        let baseSurface = appt.status == .completed ? palette[.completedCard] : palette[.card]
        let borderOpacity =
            colorScheme == .dark
            ? Self.darkSelectedBorderOpacity
            : Self.lightSelectedBorderOpacity
        return ScheduleCard.Appearance(
            systemImage: systemImage,
            background: .color(baseSurface),
            border: selectionInk.opacity(borderOpacity),
            borderStyle: StrokeStyle(lineWidth: Self.selectedBorderWidth),
            usesInnerBorder: true,
            contentOpacity: 1
        )
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
        .background(AppColor.canvas)
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
