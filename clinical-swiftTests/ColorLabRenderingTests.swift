import CoreGraphics
import SwiftUI
import Testing

@testable import clinical_swift

@MainActor
struct ColorLabRenderingTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func todayAccentOpacityIsSeparateFromAccentControl(scheme: ColorScheme) throws {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let accent = Color(.sRGB, red: 0.3, green: 0.5, blue: 0.7)
        var palette = AppPalette(overrides: [.accent: accent.opacity(0.2)])
        let todayAccent = palette.opaqueAccent(in: environment)
        #expect(palette.todaySelection.textColor(accent: todayAccent) == todayAccent)
        #expect(palette.todaySelection.highlightOpacity == 0.2)
        #expect(
            try pixels(Rectangle().fill(todayAccent), scheme: scheme)
                == pixels(Rectangle().fill(accent), scheme: scheme))
        palette.todaySelection.highlightOpacity = 0.35
        #expect(
            try pixels(
                Rectangle().fill(todayAccent.opacity(palette.todaySelection.highlightOpacity)),
                scheme: scheme)
                == pixels(Rectangle().fill(accent.opacity(0.35)), scheme: scheme))
        #expect(palette[.accent] == accent.opacity(0.2))
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func defaultsMatchOriginalStyles(scheme: ColorScheme) throws {
        #expect(
            try pixels(Rectangle().fill(AppColor.background), scheme: scheme)
                == pixels(
                    Rectangle().fill(
                        Color(.sRGB, red: 249.0 / 255, green: 249.0 / 255, blue: 250.0 / 255)),
                    scheme: scheme))
        #expect(
            try pixels(Rectangle().fill(Color("AccentColor")), scheme: scheme)
                == pixels(
                    Rectangle().fill(
                        Color(.sRGB, red: 59.0 / 255, green: 134.0 / 255, blue: 246.0 / 255)),
                    scheme: scheme))
        #expect(
            try pixels(Rectangle().fill(AppColor.accent), scheme: scheme)
                == pixels(Rectangle().fill(.tint), scheme: scheme))
        for foreground in [Color.primary, .purple] {
            for role in AppColor.allCases {
                let original = try pixels(
                    Rectangle().fill(originalStyle(role)), scheme: scheme, foreground: foreground)
                let palette = try pixels(
                    Rectangle().fill(role), scheme: scheme, foreground: foreground)
                #expect(palette == original, "Default changed for \(role.rawValue)")
            }
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func prominentButtonsUseOnlyTheirScopedAccent(scheme: ColorScheme) throws {
        let button = Button("Done", systemImage: "checkmark") {}
        // ImageRenderer does not draw native glass. Check the shared tint with bordered prominent buttons.
        let native = button.buttonStyle(.borderedProminent)
        let original = try pixels(native, scheme: scheme)
        #expect(original.contains { byte in byte != 0 })
        #expect(try pixels(button.buttonStyle(.appBorderedProminent), scheme: scheme) == original)
        var palette = AppPalette()
        palette.overrides[.accent] = .purple
        let scoped = try pixels(
            button.buttonStyle(.appBorderedProminent).environment(\.appPalette, palette),
            scheme: scheme)
        #expect(scoped == (try pixels(native.tint(.purple), scheme: scheme)))
        #expect(scoped != original)
    }

    #if DEBUG
        @Test(arguments: [ColorScheme.light, .dark])
        func accentOverrideLeavesNativeControlsUnchanged(scheme: ColorScheme) throws {
            let suite = "ColorLabRenderingTests.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let lab = ColorLab(defaults: defaults)
            let controls = HStack {
                Button("Add", systemImage: "plus") {}.buttonStyle(.bordered)
                Button("Plain", systemImage: "gearshape") {}.buttonStyle(.plain)
                Text("Text")
            }
            let original = try pixels(controls, scheme: scheme)
            let palette = try pixels(
                controls.modifier(ColorLabRoot(lab: lab)), scheme: scheme)
            #expect(palette == original)
            let accent = Rectangle().fill(AppColor.accent)
            let originalAccent = try pixels(accent.modifier(ColorLabRoot(lab: lab)), scheme: scheme)
            lab.state.colors[.accent] = .system(.purple)
            #expect(
                try pixels(controls.modifier(ColorLabRoot(lab: lab)), scheme: scheme) == original)
            #expect(
                try pixels(accent.modifier(ColorLabRoot(lab: lab)), scheme: scheme)
                    != originalAccent)
            #expect(
                try pixels(accent.modifier(ColorLabRoot(lab: lab)), scheme: scheme)
                    == pixels(Rectangle().fill(.purple), scheme: scheme))
        }
    #endif

    // Keep these source styles from PR #13 independent of AppPalette's defaults.
    private func originalStyle(_ role: AppColor) -> AnyShapeStyle {
        switch role {
        case .background: AnyShapeStyle(Color("AppBackground"))
        case .accent: AnyShapeStyle(Color.accentColor)
        case .surface: AnyShapeStyle(.background)
        case .text: AnyShapeStyle(.primary)
        case .secondaryText, .icon: AnyShapeStyle(.secondary)
        case .tertiaryText: AnyShapeStyle(.tertiary)
        case .border: AnyShapeStyle(.primary.opacity(0.12))
        case .card, .activeCard: AnyShapeStyle(Color.white)
        case .cardBorder, .grid: AnyShapeStyle(Color.gray.opacity(0.15))
        case .completedCard: AnyShapeStyle(Color(red: 0.95, green: 0.95, blue: 0.95))
        case .completedBorder: AnyShapeStyle(Color.gray.opacity(0.1))
        case .draftCard: AnyShapeStyle(Color.accentColor.opacity(0.08))
        case .draftBorder: AnyShapeStyle(Color.accentColor.opacity(0.5))
        case .activeBorder: AnyShapeStyle(Color.accentColor.opacity(0.7))
        case .time, .cardIcon: AnyShapeStyle(Color(red: 0.46, green: 0.49, blue: 0.47))
        case .unavailable: AnyShapeStyle(Color("UnavailableTimeBackground"))
        case .unavailableBorder: AnyShapeStyle(Color("UnavailableTimeBorder"))
        case .unavailableTime: AnyShapeStyle(Color("UnavailableTimeTime"))
        case .unavailableLabel: AnyShapeStyle(Color("UnavailableTimeLabel"))
        case .breakStripe: AnyShapeStyle(Color.gray.opacity(0.12))
        case .hour: AnyShapeStyle(Color.gray)
        case .now: AnyShapeStyle(Color(red: 0.78, green: 0.43, blue: 0.25))
        case .success: AnyShapeStyle(Color.green)
        case .warning: AnyShapeStyle(Color.orange)
        case .destructive: AnyShapeStyle(Color.red)
        case .onAccent, .highlight: AnyShapeStyle(Color.white)
        case .shadow: AnyShapeStyle(Color.black)
        }
    }

    private func pixels<Content: View>(
        _ content: Content, scheme: ColorScheme, foreground: Color? = nil
    ) throws -> [UInt8] {
        if let foreground {
            return try rasterize(content.foregroundStyle(foreground), scheme: scheme)
        }
        return try rasterize(content, scheme: scheme)
    }

    private func rasterize<Content: View>(_ content: Content, scheme: ColorScheme) throws -> [UInt8]
    {
        let renderer = ImageRenderer(
            content:
                content
                .frame(width: 320, height: 48)
                .environment(\.colorScheme, scheme))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        var bytes = [UInt8](repeating: 0, count: 320 * 48 * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress, width: 320, height: 48, bitsPerComponent: 8,
                    bytesPerRow: 320 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 320, height: 48))
        }
        return bytes
    }
}
