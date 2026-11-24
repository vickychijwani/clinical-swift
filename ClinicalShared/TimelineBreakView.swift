import SwiftUI

struct TimelineBreakView: View {
    struct Style: Equatable, Sendable {
        let font: Font
        let tracking: CGFloat
        let badgeHorizontalPadding: CGFloat
        let badgeVerticalPadding: CGFloat
        let stripeSpacing: CGFloat

        static let standard = Style(
            font: .caption2.weight(.medium),
            tracking: 1.4,
            badgeHorizontalPadding: 10,
            badgeVerticalPadding: 2,
            stripeSpacing: 10
        )

        static let widget = Style(
            font: .system(size: 8.5, weight: .medium),
            tracking: 1.0,
            badgeHorizontalPadding: 7,
            badgeVerticalPadding: 1.5,
            stripeSpacing: 8
        )
    }

    let scale: TimelineScale
    let availableWidth: CGFloat
    var style: Style = .standard

    var body: some View {
        ZStack {
            DiagonalStripePattern(spacing: style.stripeSpacing)
                .stroke(AppColor.breakStripe, lineWidth: 1)

            if !scale.isBreakExpanded {
                Text("\(Bitehaus.break.title.uppercased()) · \(timeRange)")
                    .font(style.font)
                    .foregroundStyle(AppColor.secondaryText.opacity(0.8))
                    .tracking(style.tracking)
                    .padding(.horizontal, style.badgeHorizontalPadding)
                    .padding(.vertical, style.badgeVerticalPadding)
                    // Mask stripes behind the label so strokes do not cross the text.
                    .background(AppColor.canvas, in: .capsule)
            }
        }
        .frame(width: width, height: scale.breakHeight)
        // Clip flush with the break bounds so stripes meet the 1 PM and 4 PM grid lines cleanly.
        .clipped()
        .position(
            x: scale.metrics.contentLeadingInset + width / 2,
            y: scale.yOffset(for: Bitehaus.break.start) + scale.breakHeight / 2
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Bitehaus.break.title), \(timeRange)")
    }

    private var width: CGFloat {
        scale.metrics.contentWidth(availableWidth: availableWidth)
    }

    private var timeRange: String {
        "\(Bitehaus.break.start.formatted(.full)) – \(Bitehaus.break.end.formatted(.full))"
    }
}

nonisolated struct DiagonalStripePattern: Shape {
    var spacing: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let overshoot: CGFloat = 2

        for offset in stride(from: -rect.height, through: rect.width, by: spacing) {
            path.move(to: CGPoint(x: offset - overshoot, y: rect.maxY + overshoot))
            path.addLine(to: CGPoint(x: offset + rect.height + overshoot, y: rect.minY - overshoot))
        }

        return path
    }
}

#Preview {
    TimelineBreakView(
        scale: TimelineScale(items: []),
        availableWidth: 390
    )
    .frame(width: 390, height: TimelineMetrics.standard.compactBreakHeight)
}
