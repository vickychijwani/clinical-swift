import SwiftUI

struct FilterBar<Selection: Hashable, Label: View>: View {
    let options: [Selection]
    @Binding var selection: Selection
    @ViewBuilder let label: (Selection) -> Label
    @Environment(\.appPalette) private var palette
    @Namespace private var selectionGlass

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    label(option)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .contentShape(.capsule)
                        .matchedGeometryEffect(id: option, in: selectionGlass)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .background {
            // Keep one glass surface alive. Replacing button effects also blurs their text.
            Color.clear
                .glassEffect(.regular, in: .capsule)
                .matchedGeometryEffect(id: selection, in: selectionGlass, isSource: false)
                .animation(
                    AppMotion.animation(.spring(duration: 0.35, bounce: 0.15)), value: selection
                )
                .allowsHitTesting(false)
        }
        .font(.system(size: 15))
        .foregroundStyle(palette[.text])
        .fixedSize(horizontal: true, vertical: true)
    }
}

#Preview {
    @Previewable @State var selection = "All"
    FilterBar(options: ["All", "Incoming", "Outgoing"], selection: $selection) { option in
        Text(option)
    }
    .padding()
}
