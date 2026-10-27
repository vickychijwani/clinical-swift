import SwiftUI

/// App-owned colors. System controls keep their native materials and state effects.
nonisolated enum AppColor: String, CaseIterable, Codable, Identifiable, ShapeStyle {
    case background = "App background"
    case accent = "Accent"
    case surface = "Panel surface"
    case text = "Primary text"
    case secondaryText = "Secondary text"
    case tertiaryText = "Tertiary text"
    case icon = "Icons"
    case border = "Panel border"
    case card = "Appointment card"
    case cardBorder = "Appointment border"
    case completedCard = "Completed card"
    case completedBorder = "Completed border"
    case draftCard = "Draft card"
    case draftBorder = "Draft border"
    case activeCard = "Active card"
    case activeBorder = "Active border"
    case time = "Appointment time"
    case cardIcon = "Appointment icons"
    case unavailable = "Unavailable card"
    case unavailableBorder = "Unavailable border"
    case unavailableTime = "Unavailable time"
    case unavailableLabel = "Unavailable label"
    case grid = "Timeline lines"
    case breakStripe = "Break stripes"
    case hour = "Timeline hours"
    case now = "Now marker"
    case success = "Success and avatars"
    case warning = "Warning"
    case destructive = "Error"
    case onAccent = "Text on accent"
    case shadow = "Shadow"
    case highlight = "Inset highlight"

    var id: Self { self }

    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        let palette = environment.appPalette
        if let color = palette.overrides[self] { return AnyShapeStyle(color) }
        // Preserve the original hierarchy. Color.secondary does not inherit a parent's foreground style.
        switch self {
        case .surface: return AnyShapeStyle(.background)
        case .text: return AnyShapeStyle(.primary)
        case .secondaryText, .icon: return AnyShapeStyle(.secondary)
        case .tertiaryText: return AnyShapeStyle(.tertiary)
        case .border where palette.overrides[.text] == nil:
            return AnyShapeStyle(.primary.opacity(0.12))
        default: return AnyShapeStyle(palette[self])
        }
    }
}

nonisolated struct AppPalette: Equatable {
    var overrides: [AppColor: Color] = [:]
    var todaySelection = TodaySelection()

    struct TodaySelection: Codable, Equatable {
        // Nil follows the accent. White and black remain optional lab overrides.
        var usesWhiteText: Bool?
        var highlightOpacity = 0.2

        func textColor(accent: Color) -> Color {
            guard let usesWhiteText else { return accent }
            return usesWhiteText ? .white : .black
        }
    }

    func opaqueAccent(in environment: EnvironmentValues) -> Color {
        var accent = self[.accent].resolve(in: environment)
        // Today text and glass tint have their own opacity, separate from the Accent control.
        accent.opacity = 1
        return Color(accent)
    }

    subscript(role: AppColor) -> Color {
        if let color = overrides[role] { return color }
        switch role {
        case .background: return Color("AppBackground")
        case .accent: return .accentColor
        case .surface: return Color("LabSystemBackground")
        case .text: return .primary
        case .secondaryText, .icon: return .secondary
        case .tertiaryText: return Color.primary.opacity(0.3)
        case .border: return self[.text].opacity(0.12)
        case .card, .activeCard: return .white
        case .cardBorder: return .gray.opacity(0.15)
        case .completedCard: return Color(red: 0.95, green: 0.95, blue: 0.95)
        case .completedBorder: return .gray.opacity(0.1)
        case .draftCard: return self[.accent].opacity(0.08)
        case .draftBorder: return self[.accent].opacity(0.5)
        case .activeBorder: return self[.accent].opacity(0.7)
        case .cardIcon: return self[.time]
        case .time: return Color(red: 0.46, green: 0.49, blue: 0.47)
        case .unavailable: return Color("UnavailableTimeBackground")
        case .unavailableBorder: return Color("UnavailableTimeBorder")
        case .unavailableTime: return Color("UnavailableTimeTime")
        case .unavailableLabel: return Color("UnavailableTimeLabel")
        case .grid: return .gray.opacity(0.15)
        case .breakStripe: return .gray.opacity(0.12)
        case .hour: return .gray
        case .now: return Color(red: 0.78, green: 0.43, blue: 0.25)
        case .success: return .green
        case .warning: return .orange
        case .destructive: return .red
        case .onAccent, .highlight: return .white
        case .shadow: return .black
        }
    }
}

nonisolated private struct AppPaletteKey: EnvironmentKey {
    static let defaultValue = AppPalette()
}

extension EnvironmentValues {
    nonisolated var appPalette: AppPalette {
        get { self[AppPaletteKey.self] }
        set { self[AppPaletteKey.self] = newValue }
    }
}

/// Keep accent tint inside prominent controls so other native buttons retain their own colors.
struct AppAccentButtonStyle<Style: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    let style: Style
    @Environment(\.appPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(style)
            .tint(palette.overrides[.accent])
    }
}

extension PrimitiveButtonStyle where Self == AppAccentButtonStyle<GlassProminentButtonStyle> {
    static var appGlassProminent: Self { Self(style: .glassProminent) }
}

extension PrimitiveButtonStyle where Self == AppAccentButtonStyle<BorderedProminentButtonStyle> {
    static var appBorderedProminent: Self { Self(style: .borderedProminent) }
}
