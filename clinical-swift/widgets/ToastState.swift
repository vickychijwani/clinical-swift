import Dependencies
import Foundation

struct ToastAction {
    let title: String
    let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.title = title
        self.handler = handler
    }
}

struct ToastItem: Identifiable {
    let id: UUID
    let message: String
    let action: ToastAction?
    let duration: Duration?

    init(
        id: UUID = UUID(),
        message: String,
        action: ToastAction? = nil,
        duration: Duration? = .seconds(4)
    ) {
        self.id = id
        self.message = message
        self.action = action
        self.duration = duration
    }

    init(
        id: UUID = UUID(),
        message: String,
        actionTitle: String,
        duration: Duration? = .seconds(4),
        action: @escaping @MainActor () -> Void
    ) {
        self.init(
            id: id,
            message: message,
            action: ToastAction(title: actionTitle, handler: action),
            duration: duration
        )
    }
}

/// Owns the single active toast and cancels stale auto-dismiss timers on replacement.
@MainActor @Observable
final class ToastStore {
    @ObservationIgnored @Dependency(\.continuousClock) private var clock

    private(set) var current: ToastItem?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    init(initialToast: ToastItem? = nil) {
        if let initialToast {
            show(initialToast)
        }
    }

    func show(_ item: ToastItem) {
        dismissTask?.cancel()
        dismissTask = nil
        current = item

        guard let duration = item.duration else { return }
        let toastID = item.id
        dismissTask = Task { [weak self] in
            do {
                try await self?.clock.sleep(for: duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.dismiss(id: toastID)
        }
    }

    func show(
        message: String,
        actionTitle: String? = nil,
        duration: Duration? = .seconds(4),
        action: (@MainActor () -> Void)? = nil
    ) {
        let toastAction =
            if let actionTitle, let action {
                ToastAction(title: actionTitle, handler: action)
            } else {
                ToastAction?.none
            }
        show(ToastItem(message: message, action: toastAction, duration: duration))
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }

    func dismiss(id: UUID) {
        guard current?.id == id else { return }
        dismiss()
    }

    func triggerAction(for id: UUID) {
        guard let item = current, item.id == id else { return }
        let handler = item.action?.handler
        dismiss()
        handler?()
    }
}
