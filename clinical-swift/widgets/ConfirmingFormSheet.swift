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
    private let content: (FormSheetDismissAction) -> Content

    @State private var selectedDetent: PresentationDetent
    @State private var isConfirmingDiscard = false

    init(
        hasUnsavedChanges: Bool,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        primaryDetent: PresentationDetent = .medium,
        dismissAttemptDetent: PresentationDetent = .height(120),
        @ViewBuilder content: @escaping (FormSheetDismissAction) -> Content
    ) {
        self.hasUnsavedChanges = hasUnsavedChanges
        self.title = title
        self.message = message
        self.primaryDetent = primaryDetent
        self.dismissAttemptDetent = dismissAttemptDetent
        self.content = content
        self._selectedDetent = State(initialValue: primaryDetent)
    }

    var body: some View {
        content(FormSheetDismissAction(attemptDismiss))
            .presentationDetents(presentationDetents, selection: $selectedDetent)
            .interactiveDismissDisabled(hasUnsavedChanges)
            .onChange(of: selectedDetent) { oldValue, newValue in
                guard newValue == dismissAttemptDetent else { return }
                selectedDetent = oldValue
                attemptDismiss()
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
        if hasUnsavedChanges {
            [primaryDetent, dismissAttemptDetent]
        } else {
            [primaryDetent]
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
