import SwiftUI

struct RadialTimeSlider: View {
    struct Status {
        let standardLabel: String
        let advisoryLabel: String
        let advisoryRange: Range<TimeOfDay>
    }

    @Binding private var selection: TimeOfDay

    private let scale: RadialTimeSliderScale
    private let status: Status

    @State private var dragStartIndex: Int?
    @State private var visualStepOffset = 0.0
    @State private var feedbackTrigger = 0

    private let pointsPerStep = 10.0
    private let degreesPerStep = 3.0
    private let visibleDegrees = 58.0

    init(
        selection: Binding<TimeOfDay>,
        in range: ClosedRange<TimeOfDay>,
        stepMinutes: Int,
        status: Status
    ) {
        self._selection = selection
        self.scale = RadialTimeSliderScale(
            range: range,
            stepMinutes: stepMinutes
        )
        self.status = status
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            tickBand

            VStack {
                Text(selection.formatted(.full))
                    .styleBodyBold()

                Text(statusLabel)
                    .styleCaption()
            }
            .padding(.bottom)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .padding()
        .background(.background)
        .clipShape(.rect(cornerRadius: 18))
        .contentShape(.rect)
        .simultaneousGesture(scrubGesture)
        .sensoryFeedback(.selection, trigger: feedbackTrigger)
    }

    private var tickBand: some View {
        Canvas { context, size in
            let selectedIndex = scale.index(for: selection)
            let center = CGPoint(x: size.width / 2, y: size.height * 0.92)
            let radius = min(size.width * 0.44, size.height * 0.78)
            let visibleTickCount = Int(visibleDegrees / degreesPerStep) + 1
            let lowerIndex = max(0, selectedIndex - visibleTickCount)
            let upperIndex = min(scale.maximumIndex, selectedIndex + visibleTickCount)

            if lowerIndex <= upperIndex {
                for index in lowerIndex...upperIndex {
                    let relativeIndex = Double(index - selectedIndex) + visualStepOffset
                    let angleOffset = relativeIndex * degreesPerStep
                    guard abs(angleOffset) <= visibleDegrees else { continue }

                    drawTick(
                        at: index,
                        angle: .degrees(-90 + angleOffset),
                        center: center,
                        radius: radius,
                        context: &context
                    )
                }
            }

            drawIndicator(
                center: center,
                radius: radius,
                context: &context
            )
        }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }

                let startIndex = dragStartIndex ?? scale.index(for: selection)
                if dragStartIndex == nil {
                    dragStartIndex = startIndex
                }

                let rawStepOffset = -Double(value.translation.width) / pointsPerStep
                let rawIndex = Double(startIndex) + rawStepOffset
                let nextIndex = min(
                    max(Int(rawIndex.rounded()), 0),
                    scale.maximumIndex
                )
                let nextSelection = scale.time(at: nextIndex)

                if selection != nextSelection {
                    selection = nextSelection
                    feedbackTrigger += 1
                }

                let residualOffset = Double(value.translation.width) / pointsPerStep
                    + Double(nextIndex - startIndex)
                visualStepOffset = rubberBandedOffset(
                    residualOffset,
                    rawIndex: rawIndex
                )
            }
            .onEnded { _ in
                dragStartIndex = nil
                withAnimation(.snappy) {
                    visualStepOffset = 0
                }
            }
    }

    private var statusLabel: String {
        status.advisoryRange.contains(selection)
            ? status.advisoryLabel
            : status.standardLabel
    }

    private func rubberBandedOffset(
        _ offset: Double,
        rawIndex: Double
    ) -> Double {
        guard rawIndex < 0 || rawIndex > Double(scale.maximumIndex) else {
            return offset
        }

        return offset.sign == .minus
            ? -log1p(abs(offset))
            : log1p(abs(offset))
    }

    private func drawTick(
        at index: Int,
        angle: Angle,
        center: CGPoint,
        radius: Double,
        context: inout GraphicsContext
    ) {
        let isMajor = scale.isMajorTick(at: index)
        let time = scale.time(at: index)
        let outerRadius = radius
        let innerRadius = radius - (isMajor ? 20 : 12)
        var path = Path()
        path.move(to: point(at: innerRadius, angle: angle, center: center))
        path.addLine(to: point(at: outerRadius, angle: angle, center: center))

        let color = status.advisoryRange.contains(time)
            ? Color.secondary.opacity(0.28)
            : Color.primary.opacity(isMajor ? 0.72 : 0.42)
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: isMajor ? 2 : 1, lineCap: .round)
        )
    }

    private func drawIndicator(
        center: CGPoint,
        radius: Double,
        context: inout GraphicsContext
    ) {
        let angle = Angle.degrees(-90)
        var path = Path()
        path.move(to: point(at: radius - 24, angle: angle, center: center))
        path.addLine(to: point(at: radius + 2, angle: angle, center: center))
        context.stroke(
            path,
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )
    }

    private func point(
        at radius: Double,
        angle: Angle,
        center: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle.radians) * radius,
            y: center.y + sin(angle.radians) * radius
        )
    }
}

#Preview("Available") {
    @Previewable @State var selection = TimeOfDay(10, 30)

    RadialTimeSlider(
        selection: $selection,
        in: TimeOfDay(9, 0)...TimeOfDay(20, 30),
        stepMinutes: 5,
        status: .init(
            standardLabel: "Available",
            advisoryLabel: "Break",
            advisoryRange: TimeOfDay(13, 0)..<TimeOfDay(16, 0)
        )
    )
    .padding()
    .background(Color("AppBackground"))
}

#Preview("Break") {
    @Previewable @State var selection = TimeOfDay(14, 0)

    RadialTimeSlider(
        selection: $selection,
        in: TimeOfDay(9, 0)...TimeOfDay(20, 30),
        stepMinutes: 5,
        status: .init(
            standardLabel: "Available",
            advisoryLabel: "Break",
            advisoryRange: TimeOfDay(13, 0)..<TimeOfDay(16, 0)
        )
    )
    .padding()
    .background(Color("AppBackground"))
}

#Preview("Endpoint") {
    @Previewable @State var selection = TimeOfDay(20, 30)

    RadialTimeSlider(
        selection: $selection,
        in: TimeOfDay(9, 0)...TimeOfDay(20, 30),
        stepMinutes: 5,
        status: .init(
            standardLabel: "Available",
            advisoryLabel: "Break",
            advisoryRange: TimeOfDay(13, 0)..<TimeOfDay(16, 0)
        )
    )
    .padding()
    .background(Color("AppBackground"))
}
