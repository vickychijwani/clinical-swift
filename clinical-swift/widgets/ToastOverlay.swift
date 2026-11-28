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
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let action = toast.action {
                    ToastActionButton(action: action, onAction: onAction)
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

private struct ToastActionButton: View {
    let action: ToastAction
    let onAction: @MainActor () -> Void

    var body: some View {
        if let systemImage = action.systemImage {
            Button(action.title, systemImage: systemImage, action: onAction)
                .labelIconToTitleSpacing(4)
                .buttonStyle(.appGlassProminent)
                .controlSize(.small)
        } else {
            Button(action.title, action: onAction)
                .buttonStyle(.appGlassProminent)
                .controlSize(.small)
        }
    }
}

enum ToastPlacement {
    case top(clearance: CGFloat = 8)
    case bottom(clearance: CGFloat = 64)

    struct Layout {
        let alignment: Alignment
        let edge: Edge
        let edgeSet: Edge.Set
        let clearance: CGFloat
    }

    var layout: Layout {
        switch self {
        case .top(let clearance):
            Layout(alignment: .top, edge: .top, edgeSet: .top, clearance: clearance)
        case .bottom(let clearance):
            Layout(alignment: .bottom, edge: .bottom, edgeSet: .bottom, clearance: clearance)
        }
    }
}

/// Floats the active toast above the TabView or active tray without changing content safe areas.
struct ToastOverlayModifier: ViewModifier {
    let store: ToastStore
    var placement: ToastPlacement = .bottom()

    private var animates: Bool { AppMotion.isEnabled }

    func body(content: Content) -> some View {
        let layout = placement.layout
        content
            .overlay(alignment: layout.alignment) {
                if let toast = store.current {
                    ToastView(
                        toast: toast,
                        onAction: { store.triggerAction(for: toast.id) },
                        onDismiss: { store.dismiss(id: toast.id) }
                    )
                    .id(toast.id)
                    .padding(.horizontal, 16)
                    .padding(layout.edgeSet, layout.clearance)
                    .transition(.move(edge: layout.edge).combined(with: .opacity))
                }
            }
            .animation(animates ? .snappy : nil, value: store.current?.id)
    }
}

extension View {
    func toastOverlay(_ store: ToastStore, placement: ToastPlacement = .bottom()) -> some View {
        modifier(ToastOverlayModifier(store: store, placement: placement))
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
