import SwiftUI

/// Keeps a sheet full-height or resizes it to fit its content.
///
/// SwiftUI parents cannot directly ask a child for its rendered size after layout. Instead,
/// the child publishes layout information upward using the preference system.
///
/// Layout hierarchy:
///
///     Sheet
///       ▼
///     FittedSheetModifier
///       ▼
///     Sheet Content
///       ├── Text
///       ├── Button
///       └── ...
///
/// The content is marked with `fittedSheetContent()`, which attaches an `anchorPreference`
/// for `.bounds`.
///
///     Sheet Content
///           ▼
///     anchorPreference(.bounds)
///           ▼
///     publishes Anchor<CGRect>
///
/// Notice that the child does **not** publish a `CGRect`.
///
/// An `Anchor<CGRect>` is a deferred reference to the content's bounds rather than the
/// bounds themselves. At the time the child is laid out, SwiftUI doesn't yet know which
/// ancestor will read the value or which coordinate space it should be expressed in.
///
/// `FittedSheetContentBoundsKey` is the `PreferenceKey` that carries this anchor from the
/// child to an ancestor. The reducer simply keeps the latest non-nil anchor if multiple
/// children publish one.
///
/// After layout completes, `overlayPreferenceValue` receives the published anchor. At this
/// point we still only have an `Anchor<CGRect>`, not an actual rectangle. A `GeometryReader`
/// is needed because its `GeometryProxy` knows how to resolve the anchor into the current
/// coordinate space.
///
///     GeometryProxy
///          ▼
///     proxy[anchor]
///          ▼
///        CGRect
///
/// From the resolved rectangle we use `maxY` as the fitted height. Since the measured
/// content begins at the top of the coordinate space, `maxY` is effectively the content's
/// height.
///
/// That height becomes a `.height(...)` `PresentationDetent`. Whenever the content's layout
/// changes, SwiftUI republishes the anchor, the rectangle is resolved again, and the sheet
/// updates to the new fitted height.
///
/// `Color.clear` exists only to provide an invisible view where `onAppear` and `onChange`
/// can observe the measured height. Hit testing is disabled so the overlay never intercepts
/// touches.
struct FittedSheetModifier: ViewModifier {
    let fitsVertically: Bool
    let fallbackDetent: PresentationDetent

    @State private var presentationDetents: Set<PresentationDetent>
    @State private var selectedDetent: PresentationDetent
    @State private var fittedDetent: PresentationDetent?

    init(
        fitsVertically: Bool,
        fallbackDetent: PresentationDetent = .large
    ) {
        self.fitsVertically = fitsVertically
        self.fallbackDetent = fallbackDetent

        let initialDetent: PresentationDetent = fitsVertically ? .medium : fallbackDetent
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
                    selectFallbackDetent()
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

    private func selectFallbackDetent() {
        presentationDetents.insert(fallbackDetent)
        selectedDetent = fallbackDetent
    }

    private func removeStaleDetents() {
        if fitsVertically {
            presentationDetents = Set([fittedDetent, selectedDetent].compactMap(\.self))
        } else {
            presentationDetents = [fallbackDetent]
        }
    }
}

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
