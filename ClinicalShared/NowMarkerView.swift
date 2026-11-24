import SwiftUI

struct NowMarkerView: View {
    let availableWidth: CGFloat
    var metrics: TimelineMetrics = .standard
    var dotSize: CGFloat = 10

    @Environment(\.appPalette) private var palette
    private var color: Color { palette[.now] }
    private let lineHeight: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(color)
                .frame(width: lineWidth, height: lineHeight)
                .position(x: lineCenterX, y: dotSize / 2)

            Circle()
                .fill(color)
                .frame(width: dotSize, height: dotSize)
                .position(x: dotCenterX, y: dotSize / 2)
        }
        .frame(width: availableWidth, height: dotSize)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var dotCenterX: CGFloat {
        metrics.contentLeadingInset - dotSize / 2
    }

    private var lineCenterX: CGFloat {
        metrics.contentLeadingInset + lineWidth / 2
    }

    private var lineWidth: CGFloat {
        metrics.contentWidth(availableWidth: availableWidth)
    }
}
