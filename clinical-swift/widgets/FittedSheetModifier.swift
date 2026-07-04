import SwiftUI

/// Keeps a sheet full-height or resizes it to fit its content.
///
/// Do not replace this modifier with `.presentationSizing(.fitted)`. SwiftUI's native fitted
/// sizing does not correctly size the app's sheet hierarchies, including sheets containing
/// `NavigationStack` and `ScrollView`; repeated attempts to use it have produced incorrect
/// results. These sheets require the explicit content measurement implemented here.
///
/// Apply the modifier to the sheet's outer container, including any `NavigationStack`, so
/// the resolved measurement includes navigation chrome. Place `fittedSheetContent()` on the
/// naturally sized content whose bottom edge ends the sheet's content. Do not mark a
/// `ScrollView`, `List`, or `Form` itself: those containers take their height from the sheet
/// viewport, creating a circular measurement. Mark their inner content instead, such as the
/// content stack inside a scroll view or the final section in a form.
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
/// The content is marked with `fittedSheetContent()`, which publishes its bounds and, when
/// applicable, its offset inside the enclosing vertical scroll view.
///
///     Sheet Content
///           ▼
///     anchorPreference(.bounds)
///           ▼
///     publishes Anchor<CGRect> + scroll offset
///
/// Notice that the child does **not** publish a `CGRect`.
///
/// An `Anchor<CGRect>` is a deferred reference to the content's bounds rather than the
/// bounds themselves. At the time the child is laid out, SwiftUI doesn't yet know which
/// ancestor will read the value or which coordinate space it should be expressed in.
///
/// `FittedSheetContentMeasurementKey` is the `PreferenceKey` that carries this measurement
/// from the child to an ancestor.
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
/// Ordinarily the resolved bounds' `maxY` is the fitted height. Content inside a `ScrollView`
/// needs one correction: scrolling moves the resolved bounds by the negative scroll offset.
/// Adding that offset back produces a stable measurement:
///
///     fitted height = resolved maxY + scroll offset
///
/// This is the same calculation for every fitted sheet. Content outside a vertical scroll
/// view has no scroll offset, reducing the formula to the original `maxY` measurement.
///
/// That height becomes a `.height(...)` `PresentationDetent`. Whenever the content's layout
/// changes, SwiftUI republishes the anchor, the rectangle is resolved again, and the sheet
/// updates to the new fitted height.
///
/// `Color.clear` exists only to provide an invisible view where `onAppear` and `onChange`
/// can observe the measured frame. Hit testing is disabled so the overlay never intercepts
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
            .overlayPreferenceValue(FittedSheetContentMeasurementKey.self) { measurement in
                GeometryReader { proxy in
                    let frame = measurement.bounds.map { proxy[$0] } ?? .zero
                    let height = frame.maxY + (measurement.scrollOffsetY ?? 0)

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

private struct FittedSheetContentMeasurement {
    var bounds: Anchor<CGRect>?
    var scrollOffsetY: CGFloat?

    nonisolated init(bounds: Anchor<CGRect>? = nil, scrollOffsetY: CGFloat? = nil) {
        self.bounds = bounds
        self.scrollOffsetY = scrollOffsetY
    }
}

private struct FittedSheetContentMeasurementKey: PreferenceKey {
    nonisolated static let defaultValue = FittedSheetContentMeasurement()

    nonisolated static func reduce(
        value: inout FittedSheetContentMeasurement,
        nextValue: () -> FittedSheetContentMeasurement
    ) {
        let nextValue = nextValue()

        if let bounds = nextValue.bounds {
            value.bounds = bounds
        }
        if let scrollOffsetY = nextValue.scrollOffsetY {
            value.scrollOffsetY = scrollOffsetY
        }
    }
}

private struct FittedSheetContentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .anchorPreference(
                key: FittedSheetContentMeasurementKey.self,
                value: .bounds
            ) { bounds in
                FittedSheetContentMeasurement(bounds: bounds)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: FittedSheetContentMeasurementKey.self,
                        value: FittedSheetContentMeasurement(
                            scrollOffsetY: proxy.bounds(of: .scrollView(axis: .vertical))?.minY
                        )
                    )
                }
            }
    }
}

extension View {
    /// Marks the content whose bottom edge should determine the fitted sheet height.
    func fittedSheetContent() -> some View {
        modifier(FittedSheetContentModifier())
    }
}
