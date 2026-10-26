import SwiftUI

struct InsetPanel<Content: View>: View {
    @Environment(\.appPalette) private var palette
    let content: Content
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.clear)
                    .shadow(color: palette[.shadow].opacity(0.18), radius: 3, x: 0, y: 2)
                    .shadow(color: palette[.highlight].opacity(0.6), radius: 4, x: 0, y: -1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(AppColor.border, lineWidth: 1)
            }
    }
}

#Preview {
    InsetPanel(cornerRadius: 16) {
        VStack {}
            .frame(width: 300, height: 300)
            .background(AppColor.background)
    }
    .frame(width: 400, height: 400)
    .background(AppColor.accent.opacity(0.3))
}
