import SwiftUI

/// Measure natural content, never a NavigationStack, ScrollView, List, or Form viewport.
/// Native fitted sizing failed for these hierarchies. Resolve the marked content's bottom
/// edge instead, with scroll offset added back so scrolling cannot change the tray height.
/// Do not replace this measurement with `.presentationSizing(.fitted)`.
/// Apply this outside navigation so its chrome is included. Mark naturally sized inner
/// content with `fittedTrayContent()`, such as the last section of a form.
struct TrayFittingModifier: ViewModifier {
    @Binding var height: CGFloat?
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(TrayContentMeasurementKey.self) { measurement in
            GeometryReader { proxy in
                let frame = measurement.bounds.map { proxy[$0] } ?? .zero
                let measured = frame.maxY + (measurement.scrollOffsetY ?? 0)
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
    var bounds: Anchor<CGRect>?
    var scrollOffsetY: CGFloat?

    nonisolated init(bounds: Anchor<CGRect>? = nil, scrollOffsetY: CGFloat? = nil) {
        self.bounds = bounds
        self.scrollOffsetY = scrollOffsetY
    }
}

private struct TrayContentMeasurementKey: PreferenceKey {
    nonisolated static let defaultValue = TrayContentMeasurement()

    nonisolated static func reduce(
        value: inout TrayContentMeasurement,
        nextValue: () -> TrayContentMeasurement
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

private struct TrayContentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .anchorPreference(
                key: TrayContentMeasurementKey.self,
                value: .bounds
            ) { bounds in
                TrayContentMeasurement(bounds: bounds)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TrayContentMeasurementKey.self,
                        value: TrayContentMeasurement(
                            scrollOffsetY: proxy.bounds(of: .scrollView(axis: .vertical))?.minY
                        )
                    )
                }
            }
    }
}

extension View {
    /// Marks the content whose bottom edge should determine the fitted tray height.
    func fittedTrayContent() -> some View {
        modifier(TrayContentModifier())
    }
}
