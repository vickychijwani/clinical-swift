import SwiftUI

extension View {
    func styleAppointmentTime(color: Color? = nil) -> some View {
        modifier(
            AppTextStyleModifier(
                font: .system(size: 12, weight: .semibold)
                    .monospacedDigit(),
                style: color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(AppColor.time),
                tracking: 0.4
            )
        )
    }

    func styleSectionTitle() -> some View {
        modifier(
            AppTextStyleModifier(
                font: .caption.bold(),
                style: AppColor.secondaryText,
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
                style: AppColor.secondaryText
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
        return AnyShapeStyle(AppColor.text)
    }

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundStyle(resolvedStyle)
            .tracking(tracking ?? 0)
            .textCase(textCase)
    }
}
