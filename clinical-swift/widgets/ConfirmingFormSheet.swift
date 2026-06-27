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
    private let primaryDetent: PresentationDetent
    private let dismissAttemptDetent: PresentationDetent
    private let allowsInteractiveDismiss: Bool
    private let content: (FormSheetDismissAction) -> Content

    @State private var selectedDetent: PresentationDetent
    @State private var isConfirmingDiscard = false

    init(
        hasUnsavedChanges: Bool,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        primaryDetent: PresentationDetent = .medium,
        dismissAttemptDetent: PresentationDetent = .height(120),
        allowsInteractiveDismiss: Bool = true,
        @ViewBuilder content: @escaping (FormSheetDismissAction) -> Content
    ) {
        self.hasUnsavedChanges = hasUnsavedChanges
        self.title = title
        self.message = message
        self.primaryDetent = primaryDetent
        self.dismissAttemptDetent = dismissAttemptDetent
        self.allowsInteractiveDismiss = allowsInteractiveDismiss
        self.content = content
        self._selectedDetent = State(initialValue: primaryDetent)
    }

    var body: some View {
        content(FormSheetDismissAction(attemptDismiss))
            .presentationDetents(presentationDetents, selection: $selectedDetent)
            .interactiveDismissDisabled(!allowsInteractiveDismiss || hasUnsavedChanges)
            .onChange(of: selectedDetent) { oldValue, newValue in
                guard allowsInteractiveDismiss else { return }
                guard newValue == dismissAttemptDetent else { return }
                selectedDetent = oldValue
                attemptDismiss()
            }
            .onChange(of: primaryDetent) {
                selectedDetent = primaryDetent
            }
            .alert(title, isPresented: $isConfirmingDiscard) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard Changes", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text(message)
            }
    }

    private var presentationDetents: Set<PresentationDetent> {
        guard allowsInteractiveDismiss else {
            return [primaryDetent]
        }

        if hasUnsavedChanges {
            return [primaryDetent, dismissAttemptDetent]
        } else {
            return [primaryDetent]
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
