import SwiftUI

struct ConfirmingTray<Content: View>: View {
    @Environment(\.trayDismiss) private var dismiss

    private let size: TraySize
    private let hasUnsavedChanges: Bool
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey
    private let allowsInteractiveDismiss: Bool
    private let content: (TrayCancelAction) -> Content

    init(
        size: TraySize,
        hasUnsavedChanges: Bool,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        allowsInteractiveDismiss: Bool = true,
        @ViewBuilder content: @escaping (TrayCancelAction) -> Content
    ) {
        self.size = size
        self.hasUnsavedChanges = hasUnsavedChanges
        self.title = title
        self.message = message
        self.allowsInteractiveDismiss = allowsInteractiveDismiss
        self.content = content
    }

    var body: some View {
        content(
            TrayCancelAction(
                title: title,
                message: message,
                hasUnsavedChanges: { hasUnsavedChanges },
                dismiss: { dismiss() }
            )
        )
        .trayOptions(
            size: size, allowsInteractiveDismiss: allowsInteractiveDismiss && !hasUnsavedChanges,
            showsIndicator: false)
    }
}

struct TrayCancelAction {
    fileprivate let title: LocalizedStringKey
    fileprivate let message: LocalizedStringKey
    private let hasUnsavedChanges: () -> Bool
    private let dismiss: () -> Void

    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        hasUnsavedChanges: @escaping () -> Bool,
        dismiss: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.hasUnsavedChanges = hasUnsavedChanges
        self.dismiss = dismiss
    }

    fileprivate var needsConfirmation: Bool {
        hasUnsavedChanges()
    }

    fileprivate func dismissTray() {
        dismiss()
    }
}

struct TrayCancelButton: View {
    let action: TrayCancelAction
    var label: LocalizedStringKey = "Cancel"

    @State private var isConfirmingDiscard = false

    var body: some View {
        Button {
            if action.needsConfirmation {
                isConfirmingDiscard = true
            } else {
                action.dismissTray()
            }
        } label: {
            Label(label, systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
        .confirmationDialog(
            action.title,
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) {
                action.dismissTray()
            }
        } message: {
            Text(action.message)
        }
    }
}
