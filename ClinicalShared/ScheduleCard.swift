import SwiftUI

struct ScheduleCard: View {
    @Environment(\.scheduleCardTuning) private var tuning

    let start: Date
    let label: String
    let appearance: Appearance
    var isDeemphasized = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch appearance.background {
            case .color(let color):
                RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
                    .fill(color)
            case .draft:
                RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
                    .fill(AppColor.activeCard)
                    // Keep underlying card edges visible as possible conflict cues.
                    .opacity(tuning.surfaceOpacity)
            }

            ScheduleCardContent(start: start, label: label, appearance: appearance)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .opacity(
                    appearance.contentOpacity * (isDeemphasized ? tuning.otherContentOpacity : 1))

            RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
                .stroke(appearance.border, style: appearance.borderStyle)
        }
        .clipShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
    }

    struct Appearance {
        let systemImage: String
        let background: Background
        let border: Color
        let borderStyle: StrokeStyle
        var contentOpacity: Double = 1
        var timeColor: Color? = nil
        var labelColor: Color? = nil
    }

    enum Background {
        case color(Color)
        case draft
    }
}

struct ScheduleCardLift: ViewModifier {
    @Environment(\.appPalette) private var palette
    @Environment(\.scheduleCardTuning) private var tuning
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
                    .fill(.black)
                    .shadow(
                        color: palette[.shadow].opacity(tuning.lift.shadowOpacity),
                        radius: isPressed ? tuning.lift.shadowRadius : 0,
                        y: isPressed ? 3 : 0
                    )
                    .overlay {
                        // Remove the shadow's interior so it cannot darken the translucent fill.
                        RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
                            .fill(.black)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .opacity(isPressed ? 1 : 0)
                    .allowsHitTesting(false)
            }
            // Keep the time edges fixed. Height and vertical position communicate the interval.
            .scaleEffect(x: isPressed ? 1 + tuning.lift.width : 1, y: 1)
            .animation(.smooth(duration: tuning.lift.duration), value: isPressed)
    }
}

private struct ScheduleCardContent: View {
    let start: Date
    let label: String
    let appearance: ScheduleCard.Appearance

    var body: some View {
        ViewThatFits(in: .vertical) {
            // Preferred: vertical layout when there's enough height
            VStack(alignment: .leading, spacing: 2) {
                Color.clear.frame(height: 4)
                ScheduleCardTime(start: start, appearance: appearance)
                ScheduleCardLabel(label: label, color: appearance.labelColor)
                Spacer(minLength: 0)
            }

            // Fallback vertical layout with slightly less spacing
            VStack(alignment: .leading) {
                Spacer(minLength: 0)
                ScheduleCardTime(start: start, appearance: appearance)
                ScheduleCardLabel(label: label, color: appearance.labelColor)
                Spacer(minLength: 0)
            }

            // Fallback: horizontal layout when vertical doesn't fit
            VStack(alignment: .leading) {
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ScheduleCardTime(start: start, appearance: appearance)
                    ScheduleCardLabel(label: label, color: appearance.labelColor)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ScheduleCardTime: View {
    @Environment(\.appPalette) private var palette
    let start: Date
    let appearance: ScheduleCard.Appearance

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: appearance.systemImage)
                .foregroundStyle(appearance.timeColor ?? palette[.cardIcon])
            Text(start.formatted(.dateTime.hour().minute()))
        }
        .styleAppointmentTime(color: appearance.timeColor)
        .layoutPriority(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ScheduleCardLabel: View {
    @Environment(\.appPalette) private var palette
    let label: String
    let color: Color?

    var body: some View {
        Text(label)
            .styleBodyBold()
            .foregroundStyle(color ?? palette[.text])
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .minimumScaleFactor(0.5)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
    }
}
