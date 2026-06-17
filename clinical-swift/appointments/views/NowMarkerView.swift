import SwiftUI

struct NowMarkerView: View {
    let metrics: TimelineMetrics
    let availableWidth: CGFloat

    private let color = Color(red: 0.78, green: 0.43, blue: 0.25)
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
        metrics.contentLeadingInset - dotSize / 2
    }

    private var lineCenterX: CGFloat {
        metrics.contentLeadingInset + lineWidth / 2
    }

    private var lineWidth: CGFloat {
        metrics.contentWidth(availableWidth: availableWidth)
    }
}
