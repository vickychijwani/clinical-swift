import SwiftUI

struct TimelineBreakView: View {
    let block: BreakBlock
    let metrics: TimelineMetrics

    static let height: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let width = metrics.contentWidth(availableWidth: geo.size.width)

            breakContent
                .frame(width: width, height: Self.height)
                .clipShape(.rect(cornerRadius: 6))
                .position(
                    x: metrics.contentLeadingInset + width / 2,
                    y: Self.height / 2
                )
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(block.title), \(timeRange)")
    }

    private var breakContent: some View {
        ZStack {
            DiagonalStripePattern()
                .stroke(.gray.opacity(0.12), lineWidth: 6)

            Text("• \(block.title.uppercased()) · \(timeRange) •")
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
                .tracking(2)
        }
    }

    private var timeRange: String {
        "\(block.start.formatted(.full)) – \(block.end.formatted(.full))"
    }
}

struct DiagonalStripePattern: Shape {
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
        block: Bitehaus.break,
        metrics: TimelineMetrics(
            hourHeight: 0,
            timeColumnWidth: 0,
            verticalPadding: 0,
            horizontalCardMargin: 0,
            verticalCardMargin: 0,
            overlapColumnSpacing: 0
        )
    )
}
