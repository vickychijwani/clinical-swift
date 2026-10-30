import SwiftUI

struct ConfirmingFormSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    private let hasUnsavedChanges: Bool
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey
    private let allowsInteractiveDismiss: Bool
    private let content: (FormSheetDismissAction) -> Content

    init(
        hasUnsavedChanges: Bool,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        allowsInteractiveDismiss: Bool = true,
        @ViewBuilder content: @escaping (FormSheetDismissAction) -> Content
    ) {
        self.hasUnsavedChanges = hasUnsavedChanges
        self.title = title
        self.message = message
        self.allowsInteractiveDismiss = allowsInteractiveDismiss
        self.content = content
    }

    var body: some View {
        content(
            FormSheetDismissAction(
                title: title,
                message: message,
                hasUnsavedChanges: { hasUnsavedChanges },
                dismiss: { dismiss() }
            )
        )
        .interactiveDismissDisabled(!allowsInteractiveDismiss || hasUnsavedChanges)
    }
}

struct FormSheetDismissAction {
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

    fileprivate func dismissSheet() {
        dismiss()
    }
}

struct FormSheetCancelButton: View {
    let action: FormSheetDismissAction
    var label: LocalizedStringKey = "Cancel"

    @State private var isConfirmingDiscard = false

    var body: some View {
        Button {
            if action.needsConfirmation {
                isConfirmingDiscard = true
            } else {
                action.dismissSheet()
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
                action.dismissSheet()
            }
        } message: {
            Text(action.message)
        }
    }
}
