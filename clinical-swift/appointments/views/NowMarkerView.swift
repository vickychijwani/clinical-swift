import SwiftUI

struct NowMarkerView: View {
    let availableWidth: CGFloat

    @Environment(\.appPalette) private var palette
    private var color: Color { palette[.now] }
    private let dotSize: CGFloat = 10
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
        Timeline.metrics.contentLeadingInset - dotSize / 2
    }

    private var lineCenterX: CGFloat {
        Timeline.metrics.contentLeadingInset + lineWidth / 2
    }

    private var lineWidth: CGFloat {
        Timeline.metrics.contentWidth(availableWidth: availableWidth)
    }
}
