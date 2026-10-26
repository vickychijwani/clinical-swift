import SwiftUI

struct TimelineHourGrid: View {
    let scale: TimelineScale
    let availableWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(scale.hourMarkers, id: \.totalMinutes) { time in
                let y = scale.yOffset(for: time)

                Rectangle()
                    .fill(AppColor.grid)
                    .frame(width: contentWidth, height: 1)
                    .position(x: contentCenterX, y: y)

                Text(time.formatted(.hourOnly))
                    .font(.caption)
                    .foregroundStyle(AppColor.hour)
                    .position(x: Timeline.metrics.timeColumnWidth - 8, y: y)
            }
        }
        .allowsHitTesting(false)
    }

    private var contentWidth: CGFloat {
        Timeline.metrics.contentWidth(availableWidth: availableWidth)
    }

    private var contentCenterX: CGFloat {
        Timeline.metrics.contentLeadingInset + contentWidth / 2
    }
}
