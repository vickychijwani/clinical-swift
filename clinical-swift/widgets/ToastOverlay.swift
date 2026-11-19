import SwiftUI

struct ToastView: View {
    let toast: ToastItem
    let onAction: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 10) {
                Text(toast.message)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let action = toast.action {
                    Button(action.title, action: onAction)
                        .buttonStyle(.appGlassProminent)
                        .controlSize(.small)
                }

                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.footnote.bold())
                    .foregroundStyle(AppColor.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("toast-dismiss")
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-toast")
    }
}

/// Floats the active toast above the TabView without changing tab content safe areas.
struct ToastOverlayModifier: ViewModifier {
    let store: ToastStore
    var bottomClearance: CGFloat = 64

    private var animates: Bool {
        #if DEBUG
            !CommandLine.arguments.contains(where: { $0.hasPrefix("--ui-testing-") })
        #else
            true
        #endif
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = store.current {
                    ToastView(
                        toast: toast,
                        onAction: { store.triggerAction(for: toast.id) },
                        onDismiss: { store.dismiss(id: toast.id) }
                    )
                    .id(toast.id)
                    .padding(.horizontal, 16)
                    .padding(.bottom, bottomClearance)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(animates ? .snappy : nil, value: store.current?.id)
    }
}

extension View {
    func toastOverlay(_ store: ToastStore, bottomClearance: CGFloat = 64) -> some View {
        modifier(ToastOverlayModifier(store: store, bottomClearance: bottomClearance))
    }
}

#Preview("Toast over TabView · Light") {
    ToastTabPreview()
        .preferredColorScheme(.light)
}

#Preview("Toast over TabView · Dark") {
    ToastTabPreview()
        .preferredColorScheme(.dark)
}

private struct ToastTabPreview: View {
    @State private var store = ToastStore(
        initialToast: ToastItem(
            message: "Appointment completed",
            actionTitle: "View",
            duration: nil
        ) {}
    )

    var body: some View {
        TabView {
            Tab("Schedule", systemImage: "calendar") {
                VStack(spacing: 16) {
                    Button("Show Toast") {
                        store.show(
                            message: "Appointment completed",
                            actionTitle: "View"
                        ) {}
                    }
                    .buttonStyle(.appGlassProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.canvas)
            }

            Tab("Patients", systemImage: "person.2") {
                Color.clear.background(AppColor.canvas)
            }

            Tab("Payments", systemImage: "indianrupeesign") {
                Color.clear.background(AppColor.canvas)
            }
        }
        .toastOverlay(store)
    }
}
