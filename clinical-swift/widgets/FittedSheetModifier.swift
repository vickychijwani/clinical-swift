import SwiftUI

private struct FittedSheetContentBoundsKey: PreferenceKey {
    nonisolated static let defaultValue: Anchor<CGRect>? = nil

    nonisolated static func reduce(
        value: inout Anchor<CGRect>?,
        nextValue: () -> Anchor<CGRect>?
    ) {
        if let nextValue = nextValue() {
            value = nextValue
        }
    }
}

/// Keeps a sheet full-height or resizes it to fit its content.
struct FittedSheetModifier: ViewModifier {
    let fitsVertically: Bool

    @State private var presentationDetents: Set<PresentationDetent>
    @State private var selectedDetent: PresentationDetent
    @State private var fittedDetent: PresentationDetent?

    init(fitsVertically: Bool) {
        self.fitsVertically = fitsVertically

        let initialDetent: PresentationDetent = fitsVertically ? .medium : .large
        _presentationDetents = State(initialValue: [initialDetent])
        _selectedDetent = State(initialValue: initialDetent)
    }

    func body(content: Content) -> some View {
        content
            .presentationDetents(presentationDetents, selection: $selectedDetent)
            .overlayPreferenceValue(FittedSheetContentBoundsKey.self) { bounds in
                GeometryReader { proxy in
                    let height = bounds.map { proxy[$0].maxY } ?? 0

                    Color.clear
                        .onAppear {
                            selectFittedDetent(height)
                        }
                        .onChange(of: height) {
                            selectFittedDetent(height)
                        }
                }
                .allowsHitTesting(false)
            }
            .onChange(of: fitsVertically) {
                if !fitsVertically {
                    selectFullHeightDetent()
                }
            }
            .transaction { transaction in
                // SwiftUI needs both heights until the resize animation finishes.
                // The animation itself is default sheet behaviour; no withAnimation {} needed
                transaction.addAnimationCompletion(criteria: .removed) {
                    removeStaleDetents()
                }
            }
    }

    private func selectFittedDetent(_ height: CGFloat) {
        guard fitsVertically, height > 0 else {
            return
        }

        let newDetent = PresentationDetent.height(height.rounded(.up))
        let previousDetent = fittedDetent
        fittedDetent = newDetent

        presentationDetents.insert(newDetent)
        selectedDetent = newDetent

        if previousDetent == newDetent {
            removeStaleDetents()
        }
    }

    private func selectFullHeightDetent() {
        presentationDetents.insert(.large)
        selectedDetent = .large
    }

    private func removeStaleDetents() {
        if fitsVertically {
            presentationDetents = Set([fittedDetent, selectedDetent].compactMap(\.self))
        } else {
            presentationDetents = [.large]
        }
    }
}

private struct FittedSheetContentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.anchorPreference(
            key: FittedSheetContentBoundsKey.self,
            value: .bounds
        ) { bounds in
            bounds
        }
    }
}

extension View {
    /// Marks the content whose bottom edge should determine the fitted sheet height.
    func fittedSheetContent() -> some View {
        modifier(FittedSheetContentModifier())
    }
}
