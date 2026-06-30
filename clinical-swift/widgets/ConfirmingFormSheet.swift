import SwiftUI

struct FormSheetDismissAction {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func callAsFunction() {
        action()
    }
}

struct ConfirmingFormSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    private let hasUnsavedChanges: Bool
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey
    private let allowsInteractiveDismiss: Bool
    private let content: (FormSheetDismissAction) -> Content

    @State private var isConfirmingDiscard = false

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
        content(FormSheetDismissAction(attemptDismiss))
            .interactiveDismissDisabled(!allowsInteractiveDismiss || hasUnsavedChanges)
            .alert(title, isPresented: $isConfirmingDiscard) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard Changes", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text(message)
            }
    }

    private func attemptDismiss() {
        if hasUnsavedChanges {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }
}
