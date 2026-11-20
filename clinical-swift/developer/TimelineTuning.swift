import SwiftUI

extension View {
    func timelineTuningRoot() -> some View {
        modifier(TimelineTuningRoot())
    }

    func timelineTuningOverlay(isVisible: Bool) -> some View {
        modifier(TimelineTuningOverlay(isVisible: isVisible))
    }
}

@MainActor @Observable
final class TimelineTuning {
    private let defaults: UserDefaults
    private static let storageKey = "developer.timelineTuning.v1"
    private static let appearanceRevisionKey = "developer.timelineTuning.appearanceRevision"

    var state: SavedState {
        didSet {
            if let data = try? JSONEncoder().encode(state) {
                defaults.set(data, forKey: Self.storageKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state =
            defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(SavedState.self, from: $0) } ?? SavedState()
        // Apply the approved values once. Later Card lab edits still persist.
        let appearanceRevision = defaults.integer(forKey: Self.appearanceRevisionKey)
        if appearanceRevision < 3 {
            let defaultsTuning = ScheduleCardTuning()
            if appearanceRevision < 1 {
                state.cards = defaultsTuning
            } else {
                if appearanceRevision < 2 {
                    state.cards.surfaceOpacity = defaultsTuning.surfaceOpacity
                }
                state.cards.overlap = defaultsTuning.overlap
            }
            if let data = try? JSONEncoder().encode(state) {
                defaults.set(data, forKey: Self.storageKey)
            }
            defaults.set(3, forKey: Self.appearanceRevisionKey)
        }
    }

    func reset() {
        state.cards = ScheduleCardTuning()
    }

    struct SavedState: Codable, Equatable {
        var isEnabled = false
        var isExpanded = true
        var position = Position()
        var cards = ScheduleCardTuning()
    }

    struct Position: Codable, Equatable {
        // Use the host size so collapse keeps the header where the user placed it.
        var x = 1.0
        var y = 1.0

        func origin(in space: CGSize, panel: CGSize, translation: CGSize = .zero) -> CGPoint {
            let travel = travel(in: space, panel: panel)
            let resting = CGPoint(
                x: min(max(x * space.width, 0), travel.width),
                y: min(max(y * space.height, 0), travel.height))
            return CGPoint(
                x: 8 + min(max(resting.x + translation.width, 0), travel.width),
                y: 8 + min(max(resting.y + translation.height, 0), travel.height))
        }

        mutating func move(by translation: CGSize, in space: CGSize, panel: CGSize) {
            let origin = origin(in: space, panel: panel, translation: translation)
            let travel = travel(in: space, panel: panel)
            if travel.width > 0 { x = (origin.x - 8) / space.width }
            if travel.height > 0 { y = (origin.y - 8) / space.height }
        }

        private func travel(in space: CGSize, panel: CGSize) -> CGSize {
            CGSize(
                width: max(0, space.width - panel.width - 16),
                height: max(0, space.height - panel.height - 16))
        }
    }
}

extension EnvironmentValues {
    @Entry var timelineTuning: TimelineTuning? = nil
}

private struct TimelineTuningRoot: ViewModifier {
    @State private var tuning = TimelineTuning()

    func body(content: Content) -> some View {
        content
            .environment(\.scheduleCardTuning, tuning.state.cards)
            .environment(\.timelineTuning, tuning)
    }
}

private struct TimelineTuningOverlay: ViewModifier {
    @Environment(\.timelineTuning) private var tuning
    @State private var availableSize = CGSize.zero
    let isVisible: Bool

    func body(content: Content) -> some View {
        if let tuning {
            content
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: {
                    availableSize = $0
                }
                .overlay(alignment: .topLeading) {
                    if tuning.state.isEnabled, isVisible {
                        TimelineTuningPanel(tuning: tuning, availableSize: availableSize)
                    }
                }
        } else {
            content
        }
    }
}

struct TimelineTuningSettings: View {
    @Environment(\.timelineTuning) private var tuning

    var body: some View {
        if let tuning {
            @Bindable var tuning = tuning
            Section("Design tools") {
                Toggle("Card lab", isOn: $tuning.state.isEnabled)
                ColorLabSettings()
            }
        }
    }
}

private struct TimelineTuningPanel: View {
    @Bindable var tuning: TimelineTuning
    let availableSize: CGSize
    @State private var panelSize = CGSize.zero
    @GestureState private var translation = CGSize.zero

    var body: some View {
        let origin = tuning.state.position.origin(
            in: availableSize, panel: panelSize, translation: translation)
        VStack(spacing: 8) {
            HStack {
                Label("Card lab", systemImage: "line.3.horizontal")
                    .bold()
                Spacer(minLength: 0)
                Button(
                    tuning.state.isExpanded ? "Collapse" : "Expand",
                    systemImage: tuning.state.isExpanded ? "chevron.down" : "chevron.up"
                ) {
                    tuning.state.isExpanded.toggle()
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 28)
            .contentShape(.rect)
            .accessibilityIdentifier("timeline-card-lab-handle")
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .updating($translation) { value, translation, _ in
                        translation = value.translation
                    }
                    .onEnded { value in
                        tuning.state.position.move(
                            by: value.translation, in: availableSize, panel: panelSize)
                    }
            )

            if tuning.state.isExpanded {
                ScrollView {
                    VStack(spacing: 10) {
                        TimelineOverlapControls(overlap: $tuning.state.cards.overlap)
                        Divider()
                        TimelineTuningSlider(
                            title: "White background", value: $tuning.state.cards.surfaceOpacity
                        )
                        TimelineTuningSlider(
                            title: "Other text & icons",
                            value: $tuning.state.cards.otherContentOpacity)
                        Divider()
                        TimelineTuningSlider(
                            title: "Press width increase",
                            value: $tuning.state.cards.lift.width,
                            range: 0...0.02, step: 0.001)
                        TimelineTuningSlider(
                            title: "Shadow opacity",
                            value: $tuning.state.cards.lift.shadowOpacity,
                            range: 0...0.3)
                        TimelineTuningSlider(
                            title: "Shadow blur", value: $tuning.state.cards.lift.shadowRadius,
                            range: 0...16, step: 1, unit: .points)
                        TimelineTuningSlider(
                            title: "Lift response", value: $tuning.state.cards.lift.duration,
                            range: 0.08...0.3, step: 0.01, unit: .seconds)
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: min(360, max(0, availableSize.height - 104)))
                HStack {
                    Button("Reset values", systemImage: "arrow.counterclockwise") {
                        tuning.reset()
                    }
                    Spacer()
                    Button("Hide", systemImage: "xmark") {
                        tuning.state.isEnabled = false
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.caption)
        .padding(12)
        .frame(
            width: min(tuning.state.isExpanded ? 288 : 188, max(0, availableSize.width - 16))
        )
        .background(.background, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.primary.opacity(0.12))
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            panelSize = $0
        }
        .offset(x: origin.x, y: origin.y)
        .accessibilityIdentifier("timeline-card-lab")
    }
}

private struct TimelineOverlapControls: View {
    @Binding var overlap: ScheduleCardTuning.Overlap

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Overlap layout", selection: $overlap.mode) {
                ForEach(ScheduleCardTuning.Overlap.Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("timeline-overlap-mode")

            if overlap.mode != .current {
                Picker("Overlap separation", selection: $overlap.separation) {
                    ForEach(ScheduleCardTuning.Overlap.Separation.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("timeline-overlap-separation")

                TimelineTuningSlider(
                    title: "Visible edge strip",
                    value: $overlap.stripWidth,
                    range: 12...36, step: 1, unit: .points)

                switch overlap.separation {
                case .halo:
                    TimelineTuningSlider(
                        title: "Halo width",
                        value: $overlap.haloWidth,
                        range: 1...4, step: 0.5, unit: .points)
                case .shadow:
                    TimelineTuningSlider(
                        title: "Overlap shadow",
                        value: $overlap.shadowOpacity,
                        range: 0...0.3)
                    TimelineTuningSlider(
                        title: "Overlap blur",
                        value: $overlap.shadowRadius,
                        range: 0...14, step: 1, unit: .points)
                case .flat:
                    EmptyView()
                }
            }
        }
    }
}

private struct TimelineTuningSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step = 0.01
    var unit = Unit.percent

    enum Unit {
        case percent, points, seconds
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                Spacer()
                Group {
                    switch unit {
                    case .percent:
                        Text(value, format: .percent.precision(.fractionLength(0...1)))
                    case .points:
                        Text("\(value, format: .number.precision(.fractionLength(0...1))) pt")
                    case .seconds:
                        Text(
                            "\(value * 1000, format: .number.precision(.fractionLength(0))) ms")
                    }
                }
                .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
        }
    }
}
