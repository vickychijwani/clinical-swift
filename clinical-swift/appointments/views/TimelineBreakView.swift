import SwiftUI

struct TimelineBreakView: View {
    let scale: TimelineScale
    let availableWidth: CGFloat

    var body: some View {
        breakContent
            .frame(width: width, height: scale.breakHeight)
            .clipShape(.rect(cornerRadius: 6))
            .position(
                x: Timeline.metrics.contentLeadingInset + width / 2,
                y: scale.yOffset(for: Bitehaus.break.start) + scale.breakHeight / 2
            )
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Bitehaus.break.title), \(timeRange)")
    }

    private var breakContent: some View {
        ZStack {
            DiagonalStripePattern()
                .stroke(AppColor.breakStripe, lineWidth: 6)

            if !scale.isBreakExpanded {
                Text("• \(Bitehaus.break.title.uppercased()) · \(timeRange) •")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(AppColor.secondaryText)
                    .tracking(2)
            }
        }
    }

    private var width: CGFloat {
        Timeline.metrics.contentWidth(availableWidth: availableWidth)
    }

    private var timeRange: String {
        "\(Bitehaus.break.start.formatted(.full)) – \(Bitehaus.break.end.formatted(.full))"
    }
}

nonisolated struct DiagonalStripePattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        for offset in stride(from: -rect.height, through: rect.width, by: 16) {
            path.move(to: CGPoint(x: offset, y: rect.maxY + 2))
            path.addLine(to: CGPoint(x: offset + rect.height, y: rect.minY - 2))
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
