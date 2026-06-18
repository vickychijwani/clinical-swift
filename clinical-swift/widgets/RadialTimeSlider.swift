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

    @State private var scrollPosition: ScrollPosition
    @State private var centeredIndex: Double
    @State private var scrollerWidth: CGFloat = 0
    @State private var feedbackTrigger = 0

    private let pointsPerStep: CGFloat = 10
    private let degreesPerStep = 2.0
    private let visibleDegrees = 40.0

    init(
        selection: Binding<TimeOfDay>,
        in range: ClosedRange<TimeOfDay>,
        stepMinutes: Int,
        status: Status
    ) {
        let scale = RadialTimeSliderScale(
            range: range,
            stepMinutes: stepMinutes
        )
        let selectedIndex = scale.index(for: selection.wrappedValue)

        self._selection = selection
        self.scale = scale
        self.status = status
        self._scrollPosition = State(
            initialValue: ScrollPosition(id: selectedIndex, anchor: .center)
        )
        self._centeredIndex = State(initialValue: Double(selectedIndex))
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

            momentumScroller
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .padding()
        .background(.background)
        .clipShape(.rect(cornerRadius: 18))
        .sensoryFeedback(.selection, trigger: feedbackTrigger)
        .onChange(of: selection) { _, newSelection in
            let newIndex = scale.index(for: newSelection)
            guard abs(centeredIndex - Double(newIndex)) > 0.5 else { return }
            scrollPosition.scrollTo(id: newIndex, anchor: .center)
        }
    }

    private var tickBand: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 3.2)
            let radius = size.width * 0.75
            let visibleTickCount = Int(visibleDegrees / degreesPerStep) + 1
            let lowerIndex = max(0, Int(centeredIndex.rounded(.down)) - visibleTickCount)
            let upperIndex = min(
                scale.maximumIndex,
                Int(centeredIndex.rounded(.up)) + visibleTickCount
            )

            if lowerIndex <= upperIndex {
                for index in lowerIndex...upperIndex {
                    let relativeIndex = Double(index) - centeredIndex
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

    private var momentumScroller: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: scrollerSideInset)

                LazyHStack(spacing: 0) {
                    ForEach(0...scale.maximumIndex, id: \.self) { index in
                        Color.clear
                            .frame(width: pointsPerStep)
                            .id(index)
                    }
                }
                .scrollTargetLayout()

                Color.clear
                    .frame(width: scrollerSideInset)
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition, anchor: .center)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        .contentShape(.rect)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.width
        } action: { _, newWidth in
            scrollerWidth = newWidth
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.x
        } action: { _, newOffset in
            updateSelection(forContentOffset: newOffset)
        }
    }

    private var statusLabel: String {
        status.advisoryRange.contains(selection)
            ? status.advisoryLabel
            : status.standardLabel
    }

    private var scrollerSideInset: CGFloat {
        max((scrollerWidth - pointsPerStep) / 2, 0)
    }

    private func updateSelection(forContentOffset contentOffset: CGFloat) {
        let newCenteredIndex = scale.fractionalIndex(
            forContentOffset: Double(contentOffset),
            pointsPerStep: Double(pointsPerStep)
        )
        centeredIndex = newCenteredIndex

        let newSelection = scale.time(at: Int(newCenteredIndex.rounded()))
        guard selection != newSelection else { return }
        selection = newSelection
        feedbackTrigger += 1
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
