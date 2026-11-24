import SwiftUI

struct TrayDismissAction {
    var id: UUID?
    var isCurrent: () -> Bool = { false }
    var dismiss: () -> Void = {}

    func callAsFunction() {
        guard isCurrent() else { return }
        dismiss()
    }
}

struct TraySurfaceMetrics: Equatable {
    var topEdge: CGFloat = 0
    var size: CGSize = .zero
    var safeArea = EdgeInsets()
    var bottomInset: CGFloat = 0
    var keyboardHeight: CGFloat = 0
    var showsIndicator = true
    var animates = true
}

extension EnvironmentValues {
    @Entry var trayDismiss = TrayDismissAction()
    @Entry var traySurfaceMetrics = TraySurfaceMetrics()
}

struct TrayOptions {
    var size: TraySize
    var allowsInteractiveDismiss: Bool
    var showsIndicator: Bool
    var dismiss: TrayDismissAction
    var requestDismiss: () -> Void
}

struct TrayOptionsKey: PreferenceKey {
    static var defaultValue: TrayOptions? { nil }

    static func reduce(value: inout TrayOptions?, nextValue: () -> TrayOptions?) {
        if let next = nextValue() { value = next }
    }
}

private struct TrayOptionsModifier: ViewModifier {
    @Environment(\.trayDismiss) private var dismiss
    let size: TraySize
    let allowsInteractiveDismiss: Bool
    let showsIndicator: Bool
    let requestDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content.transformPreference(TrayOptionsKey.self) { value in
            // A child step supplies its own size and dismissal boundary.
            if value == nil {
                value = TrayOptions(
                    size: size, allowsInteractiveDismiss: allowsInteractiveDismiss,
                    showsIndicator: showsIndicator, dismiss: dismiss,
                    requestDismiss: requestDismiss ?? { dismiss() })
            }
        }
    }
}

private struct TrayStep<Item: Identifiable & Sendable, Child: View>: ViewModifier
where Item.ID == UUID {
    @Environment(\.trayDismiss) private var parentDismiss
    @Binding var item: Item?
    let onDismiss: () -> Void
    @ViewBuilder let child: (Item) -> Child

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(item == nil ? 1 : 0)
                .allowsHitTesting(item == nil)
                .accessibilityHidden(item != nil)
                .transformPreference(TrayOptionsKey.self) { if item != nil { $0 = nil } }
            if let item {
                child(item)
                    .id(item.id)
                    .environment(
                        \.trayDismiss,
                        TrayDismissAction(
                            id: item.id,
                            isCurrent: { parentDismiss.isCurrent() && self.item?.id == item.id },
                            dismiss: { self.item = nil }))
            }
        }
        .onChange(of: item?.id) { old, new in
            if old != nil, new == nil { onDismiss() }
        }
    }
}

extension View {
    func trayOptions(
        size: TraySize, allowsInteractiveDismiss: Bool = true,
        showsIndicator: Bool = true, requestDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            TrayOptionsModifier(
                size: size, allowsInteractiveDismiss: allowsInteractiveDismiss,
                showsIndicator: showsIndicator, requestDismiss: requestDismiss))
    }

    func trayStep<Item: Identifiable & Sendable, Child: View>(
        item: Binding<Item?>, onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Item) -> Child
    ) -> some View where Item.ID == UUID {
        modifier(TrayStep(item: item, onDismiss: onDismiss, child: content))
    }
}
