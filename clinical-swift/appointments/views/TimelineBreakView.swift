import SwiftUI

struct TimelineBreakView: View {
    let scale: TimelineScale
    let availableWidth: CGFloat

    var body: some View {
        ZStack {
            DiagonalStripePattern()
                .stroke(AppColor.breakStripe, lineWidth: 1)

            if !scale.isBreakExpanded {
                Text("\(Bitehaus.break.title.uppercased()) · \(timeRange)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppColor.secondaryText.opacity(0.8))
                    .tracking(1.4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
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
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let overshoot: CGFloat = 2

        for offset in stride(from: -rect.height, through: rect.width, by: 10) {
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
    .frame(width: 390, height: Timeline.metrics.compactBreakHeight)
}
