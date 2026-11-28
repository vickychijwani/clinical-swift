import SwiftUI

struct TimelineHourGrid: View {
    struct Style: Equatable, Sendable {
        let hourFont: Font
        let hourTracking: CGFloat
        let periodFont: Font
        let periodOpacity: Double
        let periodSpacing: CGFloat
        let gridLineGap: CGFloat

        // Use proportional digits instead of tabular figures so right-aligned "11" and "12"
        // keep optical kerning without wide gaps around narrow "1" glyphs.
        static let standard = Style(
            hourFont: .system(size: 15, weight: .regular),
            hourTracking: -0.25,
            periodFont: .system(size: 9.5, weight: .regular),
            periodOpacity: 0.65,
            periodSpacing: 2,
            gridLineGap: 8
        )
        static let widget = Style(
            hourFont: .system(size: 10.5, weight: .medium),
            hourTracking: -0.2,
            periodFont: .system(size: 7, weight: .medium),
            periodOpacity: 0.65,
            periodSpacing: 1.5,
            gridLineGap: 8
        )
    }

    let scale: TimelineScale
    let availableWidth: CGFloat
    var style: Style = .standard

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(scale.hourMarkers, id: \.totalMinutes) { time in
                let y = scale.yOffset(for: time)

                Rectangle()
                    .fill(AppColor.grid)
                    .frame(width: contentWidth, height: 1)
                    .position(x: contentCenterX, y: y)

                TimelineHourLabel(time: time, style: style)
                    .frame(width: labelColumnWidth, alignment: .trailing)
                    .position(x: labelColumnWidth / 2, y: y)
            }
        }
        .allowsHitTesting(false)
    }

    private var labelColumnWidth: CGFloat {
        max(scale.metrics.contentLeadingInset - style.gridLineGap, 0)
    }

    private var contentWidth: CGFloat {
        scale.metrics.contentWidth(availableWidth: availableWidth)
    }

    private var contentCenterX: CGFloat {
        scale.metrics.contentLeadingInset + contentWidth / 2
    }
}

private struct TimelineHourLabel: View {
    let time: TimeOfDay
    let style: TimelineHourGrid.Style

    var body: some View {
        let parts = time.hourParts

        HStack(alignment: .firstTextBaseline, spacing: style.periodSpacing) {
            Text(parts.number)
                .font(style.hourFont)
                .tracking(style.hourTracking)
                .foregroundStyle(AppColor.hour)

            if !parts.period.isEmpty {
                Text(parts.period)
                    .font(style.periodFont)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.hour.opacity(style.periodOpacity))
            }
        }
        .lineLimit(1)
        // Keep the split hour and period as one static text label for UI tests.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(time.formatted(.hourOnly))
        .accessibilityAddTraits(.isStaticText)
    }
}
