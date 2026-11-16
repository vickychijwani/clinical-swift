import SwiftUI

/// Retained content is display state. The caller must still authorize saves and route changes.
@MainActor @Observable
final class TrayState<Item: Identifiable & Sendable> where Item.ID == UUID {
    enum Phase: Equatable {
        case hidden
        case entering(UUID)
        case visible(UUID)
        case exiting(UUID)
    }

    private(set) var item: Item?
    private(set) var phase: Phase = .hidden
    private(set) var surfaceID = UUID()

    func update(_ incoming: Item?, didAppear: (UUID) -> Void) {
        if let item {
            if incoming?.id != item.id {
                phase = .exiting(surfaceID)
            }
        } else if let incoming {
            item = incoming
            // A caller can reopen the same draft while its previous field tray is leaving.
            surfaceID = UUID()
            phase = .entering(surfaceID)
            // Register before entry starts so a replacement waits for this surface to leave.
            didAppear(incoming.id)
        }
    }

    func finishEntry(_ id: UUID) {
        guard phase == .entering(id) else { return }
        phase = .visible(id)
    }

    @discardableResult
    func finishExit(_ id: UUID) -> Bool {
        guard phase == .exiting(id), surfaceID == id else { return false }
        item = nil
        phase = .hidden
        return true
    }
}

nonisolated enum TraySize: Equatable, Sendable {
    case height(CGFloat)
    case medium
    case fitted
    case full
}

nonisolated struct TrayLayout: Equatable {
    let topEdge: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let bottomInset: CGFloat
    let bottomMargin: CGFloat

    /// Native floating sheets scale their full-width layout into an eight-point margin.
    /// Keep safe-area space inside that scale, including for fixed-height content.
    static func resolve(
        sizing: TraySize, size: CGSize, topInset: CGFloat,
        bottomInset: CGFloat, keyboardHeight: CGFloat = 0, fittedHeight: CGFloat? = nil
    ) -> Self {
        let floatingScale = max(0, (size.width - 16) / max(1, size.width))
        let available = max(0, size.height - topInset - 10)
        let bottom = min(max(0, bottomInset), available)
        let content: CGFloat =
            switch sizing {
            case .height(let height): max(0, height)
            case .medium:
                // Native medium uses the maximum detent space and includes the lower safe area.
                // The floating surface adds its lower safe area again, as for fixed heights.
                available / 2 + (bottom > 0 ? bottom : 38)
            case .fitted: fittedHeight ?? available
            case .full: available
            }
        let height = min(content + bottom + max(0, keyboardHeight), max(0, size.height - topInset))
        let expandedTop = size.height - height
        let floatingTop = size.height - 8 - height * floatingScale
        let upperEdge = topInset + (bottom > 0 ? 10 : 12)
        let floatingWeight = smoothUnit((expandedTop - upperEdge) / 2)
        return rendered(
            topEdge: expandedTop + (floatingTop - expandedTop) * floatingWeight,
            size: size, topInset: topInset, bottomInset: bottom)
    }

    /// Resolve the inset from the moving top edge, including every frame of a height animation.
    /// Keyboard space changes the height target; it does not select a separate width mode.
    static func rendered(
        topEdge: CGFloat, size: CGSize, topInset: CGFloat, bottomInset: CGFloat
    ) -> Self {
        let upperEdge = topInset + (bottomInset > 0 ? 10 : 12)
        let margin = 8 * smoothUnit((topEdge - upperEdge) / 26)
        let scale = max(0, (size.width - 2 * margin) / max(1, size.width))
        return Self(
            topEdge: topEdge,
            height: max(0, (size.height - margin - topEdge) / max(scale, 0.01)),
            scale: scale, bottomInset: bottomInset, bottomMargin: margin)
    }

    private static func smoothUnit(_ value: CGFloat) -> CGFloat {
        let progress = min(1, max(0, value))
        return progress * progress * (3 - 2 * progress)
    }
}

nonisolated enum TrayDrag {
    static func shouldDismiss(translation: CGSize, predicted: CGSize) -> Bool {
        translation.height > 0 && abs(translation.width) < translation.height
            && (translation.height > 80 || predicted.height > 180)
    }
}
