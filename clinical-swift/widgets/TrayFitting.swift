import SwiftUI

/// Measure natural content, never a NavigationStack, ScrollView, List, or Form viewport.
/// Native fitted sizing failed for these hierarchies. Resolve the marked sections' span
/// instead, so scrolling cannot change the tray height.
/// Do not replace this measurement with `.presentationSizing(.fitted)`.
/// Apply this outside navigation so its chrome is included. Mark the first and last
/// sections with `fittedTrayContent()` and their form with `fittedTrayScroll()`.
struct TrayFittingModifier: ViewModifier {
    @Binding var height: CGFloat?
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(TrayContentMeasurementKey.self) { measurement in
            GeometryReader { proxy in
                let frames = measurement.bounds.map { proxy[$0] }
                let viewport = measurement.viewport.map { proxy[$0] }
                let measured = viewport.map { TrayFitting.height(frames: frames, viewport: $0) } ?? 0
                let target = isEnabled ? measured.rounded(.up) : 0
                Color.clear
                    .onChange(of: target, initial: true) {
                        guard target > 0, height != target else { return }
                        height = target
                    }
            }
            .allowsHitTesting(false)
        }
    }
}
private struct TrayContentMeasurement {
    var bounds: [Anchor<CGRect>] = []
    var viewport: Anchor<CGRect>?

    nonisolated init(bounds: [Anchor<CGRect>] = [], viewport: Anchor<CGRect>? = nil) {
        self.bounds = bounds
        self.viewport = viewport
    }
}

private struct TrayContentMeasurementKey: PreferenceKey {
    nonisolated static let defaultValue = TrayContentMeasurement()

    nonisolated static func reduce(
        value: inout TrayContentMeasurement,
        nextValue: () -> TrayContentMeasurement
    ) {
        let next = nextValue()
        value.bounds.append(contentsOf: next.bounds)
        if let viewport = next.viewport { value.viewport = viewport }
    }
}

private struct TrayContentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.anchorPreference(key: TrayContentMeasurementKey.self, value: .bounds) {
            TrayContentMeasurement(bounds: [$0])
        }
    }
}

nonisolated enum TrayFitting {
    static let verticalMargin: CGFloat = 16

    static func height(frames: [CGRect], viewport: CGRect) -> CGFloat {
        guard frames.count >= 2, let first = frames.first else { return 0 }
        let span = frames.dropFirst().reduce(first) { $0.union($1) }
        // Form does not expose its scroll offset here. A section span cancels that offset.
        return viewport.minY + span.height + 2 * verticalMargin
    }
}

extension View {
    /// Marks the sections whose combined span should determine the fitted tray height.
    func fittedTrayContent() -> some View {
        modifier(TrayContentModifier())
    }

    func fittedTrayScroll() -> some View {
        // Explicit margins keep fitting independent of Form's viewport-dependent insets.
        contentMargins(.vertical, TrayFitting.verticalMargin, for: .scrollContent)
            .transformAnchorPreference(key: TrayContentMeasurementKey.self, value: .bounds) {
                value, viewport in
                value.viewport = viewport
            }
    }
}
