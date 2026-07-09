import SwiftUI

/// A button wrapper for async main-actor work that must be confirmed first.
/// It owns the confirmation dialog state and prevents repeated taps while its own confirmed action is running; shared operation state still belongs in the owning model.
struct ConfirmingAsyncButton<Label: View>: View {
    @State private var isConfirming = false
    @State private var isRunning = false

    private let role: ButtonRole?
    private let confirmationActionLabel: LocalizedStringKey
    private let message: Text
    private let action: @MainActor () async -> Void
    private let label: () -> Label

    init(
        _ confirmationActionLabel: LocalizedStringKey,
        role: ButtonRole? = nil,
        message: Text,
        action: @escaping @MainActor () async -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.confirmationActionLabel = confirmationActionLabel
        self.role = role
        self.message = message
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(role: role) {
            isConfirming = true
        } label: {
            label()
        }
        .disabled(isRunning)
        .confirmationDialog(
            "Confirm?",  // Title is hidden so it doesn't matter
            isPresented: $isConfirming,
            titleVisibility: .hidden
        ) {
            Button(confirmationActionLabel, role: role) {
                runAction()
            }
        } message: {
            message
        }
    }

    private func runAction() {
        guard !isRunning else {
            return
        }

        isRunning = true
        Task { @MainActor in
            defer { isRunning = false }
            await action()
        }
    }
}
