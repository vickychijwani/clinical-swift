import SwiftUI

/// A button wrapper for actions that immediately start async main-actor work.
/// It prevents repeated taps while its own action is running; shared operation state still belongs in the owning model.
struct AsyncButton<Label: View>: View {
    @State private var isRunning = false

    private let action: @MainActor () async -> Void
    private let label: () -> Label

    init(
        action: @escaping @MainActor () async -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.action = action
        self.label = label
    }

    var body: some View {
        Button {
            guard !isRunning else {
                return
            }

            isRunning = true
            Task { @MainActor in
                defer { isRunning = false }
                await action()
            }
        } label: {
            label()
        }
        .disabled(isRunning)
    }
}

extension AsyncButton where Label == SwiftUI.Label<Text, Image> {
    init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        action: @escaping @MainActor () async -> Void
    ) {
        self.init(action: action) {
            SwiftUI.Label(titleKey, systemImage: systemImage)
        }
    }
}
