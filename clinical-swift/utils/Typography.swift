import SwiftUI

extension Text {
    func styleAppointmentTime() -> some View {
        self.modifier(
            AppTextStyleModifier(
                font: .system(size: 12, weight: .semibold)
                    .monospacedDigit(),
                color: Color(red: 0.46, green: 0.49, blue: 0.47),
                tracking: 0.4
            )
        )
    }

    func styleBodyBold() -> some View {
        self.modifier(
            AppTextStyleModifier(font: .system(size: 14, weight: .semibold))
        )
    }

    func styleCaption() -> some View {
        self.modifier(
            AppTextStyleModifier(
                font: .system(size: 12, weight: .regular),
                style: .secondary
            )
        )
    }
}

struct AppTextStyleModifier: ViewModifier {
    var font: Font? = nil
    var style: AnyShapeStyle? = nil
    var color: Color? = nil

    /// Letter spacing.
    var tracking: Double? = nil

    init(
        font: Font,
        color: Color? = nil,
        tracking: Double? = nil
    ) {
        self.font = font
        self.color = color
        self.style = nil
        self.tracking = tracking
    }

    init<Style: ShapeStyle>(
        font: Font,
        style: Style,
        tracking: Double? = nil
    ) {
        self.font = font
        self.color = nil
        self.style = AnyShapeStyle(style)
        self.tracking = tracking
    }

    private var resolvedStyle: AnyShapeStyle {
        if let style {
            return style
        }
        if let color {
            return AnyShapeStyle(color)
        }
        return AnyShapeStyle(.primary)
    }

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundStyle(resolvedStyle)
            .tracking(tracking ?? 0)
    }
}
