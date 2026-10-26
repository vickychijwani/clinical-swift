import SwiftUI

extension View {
    func colorLabRoot() -> some View {
        #if DEBUG
            modifier(ColorLabRoot())
        #else
            self
        #endif
    }

    func colorLabOverlay() -> some View {
        #if DEBUG
            modifier(ColorLabOverlay())
        #else
            self
        #endif
    }
}

#if DEBUG
    @MainActor @Observable
    final class ColorLab {
        private let defaults: UserDefaults
        private static let key = "developer.colorLab.v1"

        var state: SavedState {
            didSet {
                if let data = try? JSONEncoder().encode(state) {
                    defaults.set(data, forKey: Self.key)
                }
            }
        }

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
            state =
                defaults.data(forKey: Self.key)
                .flatMap { try? JSONDecoder().decode(SavedState.self, from: $0) } ?? SavedState()
        }

        var palette: AppPalette {
            AppPalette(
                overrides: state.colors.mapValues(\.color),
                todaySelection: state.todaySelection ?? .init())
        }

        func reset() {
            state.colors = [:]
            state.todaySelection = nil
        }

        struct SavedState: Codable, Equatable {
            var isEnabled = false
            var isExpanded = true
            var position = TimelineTuning.Position(x: 0, y: 0)
            var selected = AppColor.background
            var colors: [AppColor: Selection] = [:]
            var todaySelection: AppPalette.TodaySelection?
        }

        enum Selection: Codable, Equatable {
            case custom(RGBA)
            case system(SystemColor)

            var color: Color {
                switch self {
                case .custom(let rgba): rgba.color
                case .system(let system): system.color
                }
            }
        }

        enum SystemColor: String, CaseIterable, Codable, Identifiable {
            case primary, secondary, tertiary, background
            case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown
            case gray, white, black, clear

            var id: Self { self }
            var color: Color {
                switch self {
                case .primary: .primary
                case .secondary: .secondary
                case .tertiary: Color.primary.opacity(0.3)
                case .background: Color("LabSystemBackground")
                case .red: .red
                case .orange: .orange
                case .yellow: .yellow
                case .green: .green
                case .mint: .mint
                case .teal: .teal
                case .cyan: .cyan
                case .blue: .blue
                case .indigo: .indigo
                case .purple: .purple
                case .pink: .pink
                case .brown: .brown
                case .gray: .gray
                case .white: .white
                case .black: .black
                case .clear: .clear
                }
            }
        }

        struct RGBA: Codable, Equatable {
            var red: Double
            var green: Double
            var blue: Double
            var alpha: Double

            var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

            init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
                self.red = red
                self.green = green
                self.blue = blue
                self.alpha = alpha
            }

            init(_ color: Color, in environment: EnvironmentValues) {
                let value = color.resolve(in: environment)
                red = min(1, max(0, Double(value.red)))
                green = min(1, max(0, Double(value.green)))
                blue = min(1, max(0, Double(value.blue)))
                alpha = Double(value.opacity)
            }

            var hex: String {
                "#"
                    + [red, green, blue].map { channel in
                        let byte = Int((min(1, max(0, channel)) * 255).rounded())
                        let digits = String(byte, radix: 16, uppercase: true)
                        return digits.count == 1 ? "0" + digits : digits
                    }.joined()
            }

            init?(hex: String, alpha: Double) {
                var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                if digits.hasPrefix("#") { digits.removeFirst() }
                guard digits.utf8.count == 6,
                    digits.utf8.allSatisfy({
                        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
                    }),
                    let value = Int(digits, radix: 16)
                else { return nil }
                self.init(
                    red: Double((value >> 16) & 255) / 255,
                    green: Double((value >> 8) & 255) / 255,
                    blue: Double(value & 255) / 255, alpha: alpha)
            }

            var hsl: HSL {
                let high = max(red, green, blue)
                let low = min(red, green, blue)
                let delta = high - low
                let lightness = (high + low) / 2
                guard delta > 0 else { return HSL(hue: 0, saturation: 0, lightness: lightness) }
                let segment: Double
                if high == red {
                    segment = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
                } else if high == green {
                    segment = (blue - red) / delta + 2
                } else {
                    segment = (red - green) / delta + 4
                }
                return HSL(
                    hue: (segment * 60 + 360).truncatingRemainder(dividingBy: 360),
                    saturation: delta / (1 - abs(2 * lightness - 1)), lightness: lightness)
            }

            init(hsl: HSL, alpha: Double) {
                let hue = (hsl.hue / 60).truncatingRemainder(dividingBy: 6)
                let chroma = (1 - abs(2 * hsl.lightness - 1)) * hsl.saturation
                let x = chroma * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
                let match = hsl.lightness - chroma / 2
                let channels: (Double, Double, Double)
                switch hue {
                case ..<1: channels = (chroma, x, 0)
                case ..<2: channels = (x, chroma, 0)
                case ..<3: channels = (0, chroma, x)
                case ..<4: channels = (0, x, chroma)
                case ..<5: channels = (x, 0, chroma)
                default: channels = (chroma, 0, x)
                }
                self.init(
                    red: channels.0 + match, green: channels.1 + match,
                    blue: channels.2 + match, alpha: alpha)
            }
        }

        struct HSL: Equatable {
            var hue: Double
            var saturation: Double
            var lightness: Double
        }
    }

    extension EnvironmentValues {
        @Entry var colorLab: ColorLab? = nil
    }

    struct ColorLabRoot: ViewModifier {
        @State var lab = ColorLab()

        func body(content: Content) -> some View {
            content
                .environment(\.colorLab, lab)
                // A root tint also recolors native controls. Apply overrides through app color roles only.
                .environment(\.appPalette, lab.palette)
        }
    }

    private struct ColorLabOverlay: ViewModifier {
        @Environment(\.colorLab) private var lab
        @State private var availableSize = CGSize.zero

        func body(content: Content) -> some View {
            content
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: {
                    availableSize = $0
                }
                .overlay(alignment: .topLeading) {
                    if let lab, lab.state.isEnabled {
                        ColorLabPanel(lab: lab, availableSize: availableSize)
                            // The tool must stay readable when app colors have low contrast.
                            .environment(\.appPalette, AppPalette())
                            .foregroundStyle(.primary)
                            .tint(.blue)
                    }
                }
        }
    }

    struct ColorLabSettings: View {
        @Environment(\.colorLab) private var lab

        var body: some View {
            if let lab {
                @Bindable var lab = lab
                Toggle("Color lab", isOn: $lab.state.isEnabled)
            }
        }
    }

    private struct ColorLabPanel: View {
        @Bindable var lab: ColorLab
        let availableSize: CGSize
        @State private var panelSize = CGSize.zero
        @GestureState private var translation = CGSize.zero

        var body: some View {
            let origin = lab.state.position.origin(
                in: availableSize, panel: panelSize, translation: translation)
            VStack(spacing: 8) {
                HStack {
                    Label("Color lab", systemImage: "line.3.horizontal").bold()
                    Spacer(minLength: 0)
                    Button(
                        lab.state.isExpanded ? "Collapse" : "Expand",
                        systemImage: lab.state.isExpanded ? "chevron.down" : "chevron.up"
                    ) {
                        lab.state.isExpanded.toggle()
                    }
                    .labelStyle(.iconOnly)
                }
                .frame(minHeight: 28)
                .contentShape(.rect)
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .updating($translation) { value, translation, _ in
                            translation = value.translation
                        }
                        .onEnded { value in
                            lab.state.position.move(
                                by: value.translation, in: availableSize, panel: panelSize)
                        })
                if lab.state.isExpanded {
                    ScrollView {
                        VStack {
                            ColorLabTodaySelection(lab: lab)
                            Divider()
                            ColorLabEditor(lab: lab)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: min(420, max(0, availableSize.height - 110)))
                    HStack {
                        Button("Reset all", systemImage: "arrow.counterclockwise") { lab.reset() }
                        Spacer()
                        Button("Hide", systemImage: "xmark") { lab.state.isEnabled = false }
                    }
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(12)
            .frame(width: min(lab.state.isExpanded ? 300 : 188, max(0, availableSize.width - 16)))
            .background(.background, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.12))
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                panelSize = $0
            }
            .offset(x: origin.x, y: origin.y)
            .accessibilityIdentifier("color-lab")
        }
    }

    private struct ColorLabTodaySelection: View {
        @Bindable var lab: ColorLab

        private var selection: Binding<AppPalette.TodaySelection> {
            Binding(
                get: { lab.state.todaySelection ?? .init() },
                set: { lab.state.todaySelection = $0 })
        }

        var body: some View {
            VStack(alignment: .leading) {
                Text("Today selected").bold()
                Picker("Text color", selection: selection.usesWhiteText) {
                    Text("White").tag(true)
                    Text("Black").tag(false)
                }
                .pickerStyle(.segmented)
                ColorLabChannel(
                    title: "Highlight opacity %",
                    value: Binding(
                        get: { selection.wrappedValue.highlightOpacity * 100 },
                        set: { selection.wrappedValue.highlightOpacity = $0 / 100 }),
                    range: 0...100)
            }
        }
    }

    private struct ColorLabEditor: View {
        @Bindable var lab: ColorLab
        @Environment(\.self) private var environment
        @State private var mode = Mode.hex
        @State private var hslDraft: ColorLab.HSL?
        @State private var hslSource: ColorLab.RGBA?

        private enum Mode: String, CaseIterable {
            case hex = "Hex"
            case rgb = "RGB"
            case hsl = "HSL"
        }

        private var rgba: ColorLab.RGBA {
            if case .custom(let value) = lab.state.colors[lab.state.selected] { return value }
            return ColorLab.RGBA(lab.palette[lab.state.selected], in: environment)
        }

        private var currentHSL: ColorLab.HSL {
            hslSource == rgba ? (hslDraft ?? rgba.hsl) : rgba.hsl
        }

        var body: some View {
            VStack(spacing: 10) {
                Picker("Color", selection: $lab.state.selected) {
                    ForEach(AppColor.allCases) { role in Text(role.rawValue).tag(role) }
                }
                .pickerStyle(.menu)
                ColorPicker(
                    "Palette",
                    selection: Binding(
                        get: { lab.palette[lab.state.selected] },
                        set: {
                            lab.state.colors[lab.state.selected] = .custom(
                                .init($0, in: environment))
                        }))
                Picker(
                    "System color",
                    selection: Binding<ColorLab.SystemColor?>(
                        get: {
                            if case .system(let color) = lab.state.colors[lab.state.selected] {
                                return color
                            }
                            return nil
                        },
                        set: {
                            if let color = $0 {
                                lab.state.colors[lab.state.selected] = .system(color)
                            }
                        }
                    )
                ) {
                    Text("Default or custom").tag(Optional<ColorLab.SystemColor>.none)
                    ForEach(ColorLab.SystemColor.allCases) { color in
                        Text(color.rawValue.capitalized).tag(Optional(color))
                    }
                }
                .pickerStyle(.menu)
                Picker("Channels", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if mode == .hex {
                    ColorLabHexField(
                        value: Binding(
                            get: { rgba },
                            set: { lab.state.colors[lab.state.selected] = .custom($0) })
                    )
                    .id(lab.state.selected)
                } else if mode == .rgb {
                    ColorLabChannel(title: "Red", value: rgb(\.red), range: 0...255)
                    ColorLabChannel(title: "Green", value: rgb(\.green), range: 0...255)
                    ColorLabChannel(title: "Blue", value: rgb(\.blue), range: 0...255)
                } else {
                    ColorLabChannel(title: "Hue °", value: hsl(\.hue, scale: 1), range: 0...360)
                    ColorLabChannel(
                        title: "Saturation %", value: hsl(\.saturation, scale: 100), range: 0...100)
                    ColorLabChannel(
                        title: "Lightness %", value: hsl(\.lightness, scale: 100), range: 0...100)
                }
                ColorLabChannel(title: "Opacity %", value: rgb(\.alpha, scale: 100), range: 0...100)
                Button("Reset this color", systemImage: "arrow.uturn.backward") {
                    lab.state.colors[lab.state.selected] = nil
                }
                Text("Changes apply at once and stay on this device. Hide keeps your colors.")
                    .foregroundStyle(.secondary)
            }
            .onChange(of: lab.state.selected) {
                hslDraft = nil
                hslSource = nil
            }
        }

        private func rgb(_ path: WritableKeyPath<ColorLab.RGBA, Double>, scale: Double = 255)
            -> Binding<Double>
        {
            Binding(
                get: { rgba[keyPath: path] * scale },
                set: {
                    var value = rgba
                    value[keyPath: path] = $0 / scale
                    lab.state.colors[lab.state.selected] = .custom(value)
                })
        }

        private func hsl(_ path: WritableKeyPath<ColorLab.HSL, Double>, scale: Double) -> Binding<
            Double
        > {
            Binding(
                get: { currentHSL[keyPath: path] * scale },
                set: {
                    var value = currentHSL
                    value[keyPath: path] = $0 / scale
                    // Retain hue and saturation at black, white, and gray so the next channel edit can use them.
                    let next = ColorLab.RGBA(hsl: value, alpha: rgba.alpha)
                    hslDraft = value
                    hslSource = next
                    lab.state.colors[lab.state.selected] = .custom(next)
                })
        }
    }

    private struct ColorLabHexField: View {
        @Binding var value: ColorLab.RGBA
        @State private var text = ""
        @FocusState private var isFocused: Bool

        var body: some View {
            VStack(alignment: .leading) {
                TextField(
                    "#RRGGBB",
                    text: Binding(
                        get: { text },
                        set: { input in
                            text = input
                            // Only text entry writes a color. Showing the rounded hex value must not convert a source color.
                            if let next = ColorLab.RGBA(hex: input, alpha: value.alpha) {
                                value = next
                            }
                        })
                )
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .monospaced()
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { isFocused = false }
                Text("Use six hex digits. Opacity is separate.")
                    .foregroundStyle(.secondary)
            }
            .onAppear { text = value.hex }
            .onChange(of: value) { previous, next in
                // Keep unfinished input while opacity changes. Palette and role changes update the hex value.
                if previous.hex != next.hex { text = next.hex }
            }
        }
    }

    private struct ColorLabChannel: View {
        let title: String
        @Binding var value: Double
        let range: ClosedRange<Double>
        @FocusState private var isFocused: Bool

        var body: some View {
            let bounded = Binding(
                get: { value },
                set: { value = min(range.upperBound, max(range.lowerBound, $0)) })
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                    Spacer()
                    TextField(title, value: bounded, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .focused($isFocused)
                }
                Slider(value: bounded, in: range, step: 1) { Text(title) }
            }
            .monospacedDigit()
            .toolbar {
                if isFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isFocused = false }
                    }
                }
            }
        }
    }
#endif
