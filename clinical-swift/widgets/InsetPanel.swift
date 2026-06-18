import SwiftUI

struct InsetPanel<Content: View>: View {
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
                    .fill(.background)
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 2)
                    .shadow(color: .white.opacity(0.6), radius: 4, x: 0, y: -1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.primary.opacity(0.12), lineWidth: 1)
            }
    }
}

#Preview {
    InsetPanel(cornerRadius: 16) {
        VStack {}
            .frame(width: 300, height: 300)
            .background(Color("AppBackground"))
    }
    .frame(width: 400, height: 400)
    .background(Color("AccentColor").opacity(0.3))
}
