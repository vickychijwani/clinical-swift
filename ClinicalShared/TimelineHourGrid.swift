import SwiftUI

struct TimelineHourGrid: View {
    struct Style: Equatable, Sendable {
        let hourFont: Font
        let alignsTrailingInTimeColumn: Bool

        static let standard = Style(hourFont: .caption, alignsTrailingInTimeColumn: false)
        static let widget = Style(
            hourFont: .system(size: 9.5, weight: .medium).monospacedDigit(),
            alignsTrailingInTimeColumn: true
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

                if style.alignsTrailingInTimeColumn {
                    Text(time.formatted(.hourOnly))
                        .font(style.hourFont)
                        .foregroundStyle(AppColor.hour)
                        .lineLimit(1)
                        .frame(width: scale.metrics.timeColumnWidth, alignment: .trailing)
                        .position(x: scale.metrics.timeColumnWidth / 2, y: y)
                } else {
                    Text(time.formatted(.hourOnly))
                        .font(style.hourFont)
                        .foregroundStyle(AppColor.hour)
                        .position(x: scale.metrics.timeColumnWidth - 8, y: y)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var contentWidth: CGFloat {
        scale.metrics.contentWidth(availableWidth: availableWidth)
    }

    private var contentCenterX: CGFloat {
        scale.metrics.contentLeadingInset + contentWidth / 2
    }
}
