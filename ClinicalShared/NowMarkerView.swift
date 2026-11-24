import ClinicalModels
import SwiftUI

struct NowMarkerView: View {
    enum Indicator {
        case dot(size: CGFloat = 10)
        case time(Date)
    }

    let availableWidth: CGFloat
    var metrics: TimelineMetrics = .standard
    var indicator: Indicator = .dot()

    @Environment(\.appPalette) private var palette
    private var color: Color { palette[.now] }

    var body: some View {
        Group {
            switch indicator {
            case .dot(let dotSize):
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(color)
                        .frame(width: lineWidth, height: 1)
                        .position(x: lineCenterX, y: dotSize / 2)

                    Circle()
                        .fill(color)
                        .frame(width: dotSize, height: dotSize)
                        .position(x: metrics.contentLeadingInset - dotSize / 2, y: dotSize / 2)
                }
                .frame(width: availableWidth, height: dotSize)

            case .time(let date):
                HStack(spacing: 0) {
                    Text(Self.formattedTime(date))
                        .font(.caption.bold())
                        .monospacedDigit()
                        .foregroundStyle(palette[.onAccent])
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .frame(width: badgeWidth)
                        .background(color, in: .capsule)
                        .frame(width: metrics.contentLeadingInset, alignment: .trailing)

                    Rectangle()
                        .fill(color)
                        .frame(width: lineWidth, height: 1.5)
                }
                .frame(width: availableWidth, alignment: .leading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    nonisolated static func formattedTime(_ date: Date) -> String {
        date.formatted(ClinicDate.formatStyle.hour(.defaultDigits(amPM: .omitted)).minute())
    }

    private var badgeWidth: CGFloat {
        // Center the capsule over the hour labels while matching the trailing 8pt margin.
        max(metrics.contentLeadingInset - 8, 0)
    }

    private var lineCenterX: CGFloat {
        metrics.contentLeadingInset + lineWidth / 2
    }

    private var lineWidth: CGFloat {
        metrics.contentWidth(availableWidth: availableWidth)
    }
}

#Preview("Time capsule") {
    NowMarkerView(
        availableWidth: 390,
        indicator: .time(TimeOfDay(14, 30).today)
    )
    .padding(.vertical, 20)
    .background(AppColor.canvas)
}

#Preview("Widget dot") {
    NowMarkerView(
        availableWidth: 340,
        indicator: .dot(size: 7)
    )
    .padding(.vertical, 20)
    .background(AppColor.canvas)
}
