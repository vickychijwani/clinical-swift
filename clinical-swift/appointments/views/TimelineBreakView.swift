import SwiftUI

struct TimelineBreakView: View {
    static let height: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let width = Timeline.metrics.contentWidth(availableWidth: geo.size.width)

            breakContent
                .frame(width: width, height: Self.height)
                .clipShape(.rect(cornerRadius: 6))
                .position(
                    x: Timeline.metrics.contentLeadingInset + width / 2,
                    y: Self.height / 2
                )
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Bitehaus.break.title), \(timeRange)")
    }

    private var breakContent: some View {
        ZStack {
            DiagonalStripePattern()
                .stroke(.gray.opacity(0.12), lineWidth: 6)

            Text("• \(Bitehaus.break.title.uppercased()) · \(timeRange) •")
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
                .tracking(2)
        }
    }

    private var timeRange: String {
        "\(Bitehaus.break.start.formatted(.full)) – \(Bitehaus.break.end.formatted(.full))"
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
    TimelineBreakView()
}
