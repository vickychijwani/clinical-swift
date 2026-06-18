import SwiftUI

struct ClippedView<Content: View>: View {
    let content: Content
    let height: CGFloat
    let yOffset: CGFloat
    let cornerRadius: CGFloat = 16

    init(height: CGFloat, yOffset: CGFloat, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.height = height
        self.yOffset = yOffset
    }

    var body: some View {
        InsetPanel(cornerRadius: cornerRadius) {
            content.clippedHeight(height, yOffset: yOffset, cornerRadius: cornerRadius)
        }
    }
}

extension View {
    fileprivate func clippedHeight(
        _ height: CGFloat,
        yOffset: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        self
            .fixedSize(horizontal: false, vertical: true)
            .offset(y: -yOffset)
            .frame(height: height, alignment: .top)
            .clipped()
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

#Preview {
    ClippedView(height: 240, yOffset: 60) {
        sampleTimeline()
    }
}
