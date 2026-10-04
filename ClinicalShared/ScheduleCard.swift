import SwiftUI

struct ScheduleCard: View {
    let start: Date
    let label: String
    let appearance: Appearance

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
                .fill(appearance.background)

            ScheduleCardContent(start: start, label: label, appearance: appearance)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .opacity(appearance.contentOpacity)

            RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
                .stroke(appearance.border, style: appearance.borderStyle)
        }
        .clipShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
    }

    struct Appearance {
        let systemImage: String
        let background: Color
        let border: Color
        let borderStyle: StrokeStyle
        var contentOpacity: Double = 1
        var timeColor: Color? = nil
        var labelColor: Color = .primary
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
    let start: Date
    let appearance: ScheduleCard.Appearance

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: appearance.systemImage)
            Text(start.formatted(.dateTime.hour().minute()))
        }
        .styleAppointmentTime(color: appearance.timeColor)
        .layoutPriority(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ScheduleCardLabel: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .styleBodyBold()
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .minimumScaleFactor(0.5)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
    }
}
