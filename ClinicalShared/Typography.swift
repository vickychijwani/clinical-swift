import SwiftUI

extension View {
    func styleAppointmentTime() -> some View {
        modifier(
            AppTextStyleModifier(
                font: .system(size: 12, weight: .semibold)
                    .monospacedDigit(),
                color: Color(red: 0.46, green: 0.49, blue: 0.47),
                tracking: 0.4
            )
        )
    }

    func styleSectionTitle() -> some View {
        modifier(
            AppTextStyleModifier(
                font: .caption.bold(),
                style: .secondary,
                textCase: .uppercase
            )
        )
    }

    func styleFormPicker() -> some View {
        modifier(AppTextStyleModifier(font: .system(size: 16, weight: .regular)))
    }

    func styleBodyBold() -> some View {
        modifier(AppTextStyleModifier(font: .system(size: 14, weight: .semibold)))
    }

    func styleCaption() -> some View {
        modifier(
            AppTextStyleModifier(
                font: .system(size: 12, weight: .regular),
                style: .secondary
            )
        )
    }
}

struct AppTextStyleModifier: ViewModifier {
    var font: Font?
    var style: AnyShapeStyle?
    var color: Color?
    var tracking: Double?
    var textCase: Text.Case?

    init(
        font: Font,
        color: Color? = nil,
        tracking: Double? = nil,
        textCase: Text.Case? = nil
    ) {
        self.font = font
        self.color = color
        style = nil
        self.tracking = tracking
        self.textCase = textCase
    }

    init<Style: ShapeStyle>(
        font: Font,
        style: Style,
        tracking: Double? = nil,
        textCase: Text.Case? = nil
    ) {
        self.font = font
        color = nil
        self.style = AnyShapeStyle(style)
        self.tracking = tracking
        self.textCase = textCase
    }

    private var resolvedStyle: AnyShapeStyle {
        if let style { return style }
        if let color { return AnyShapeStyle(color) }
        return AnyShapeStyle(.primary)
    }

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundStyle(resolvedStyle)
            .tracking(tracking ?? 0)
            .textCase(textCase)
    }
}
