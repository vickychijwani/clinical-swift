import ClinicalModels
import Foundation
import Observation

/// Cooldown that keeps a drag or hold release from firing a card tap in the same touch event.
struct TimelineDragCooldown {
    private var lastInteraction: ContinuousClock.Instant?

    var allowsSelection: Bool {
        allowsSelection(at: .now)
    }

    func allowsSelection(at now: ContinuousClock.Instant) -> Bool {
        // A hold can finish in the same event as the button release.
        lastInteraction.map { $0.duration(to: now) > .milliseconds(150) } ?? true
    }

    mutating func record(at now: ContinuousClock.Instant = .now) {
        lastInteraction = now
    }
}

/// Gestures change only the editor's draft in memory.
/// The editor owns saving and errors.
@MainActor @Observable
final class TimelineAdjustment {
    enum Edge { case move, duration }

    private(set) var original: TimelineItem?
    private(set) var edge: Edge = .move
    private(set) var isDragging = false
    private(set) var hoverRequest: UUID?
    private var dragCooldown = TimelineDragCooldown()
    private var expanded = false
    private var anchorY: CGFloat = 0
    private var translation: CGFloat = 0

    var allowsSelection: Bool {
        dragCooldown.allowsSelection
    }

    func items(_ items: [TimelineItem], draft: TimelineItem, on date: Date? = nil) -> [TimelineItem]
    {
        let date = date ?? items.first?.start ?? draft.start
        var items = items.filter { $0.id != draft.id }
        if draft.start.isSameDayAs(date) {
            items.append(draft)
        }
        return items
    }

    func scale(_ items: [TimelineItem], draft: TimelineItem, on date: Date? = nil) -> TimelineScale
    {
        let displayed = self.items(items, draft: draft, on: date)
        guard isDragging,
            displayed.contains(where: { $0.id == draft.id })
        else { return TimelineScale(items: displayed) }
        let others = displayed.filter { $0.id != draft.id }
        return TimelineScale(
            items: others,
            breakPresentation: expanded || TimelineScale(items: others).isBreakExpanded
                ? .expanded : .compact
        )
    }

    func begin(_ item: TimelineItem, edge: Edge, items: [TimelineItem]) {
        guard !isDragging, item.allowsAdjustment else { return }
        dragCooldown.record()
        original = item
        self.edge = edge
        expanded = TimelineScale(items: items).isBreakExpanded
        let time =
            edge == .duration
            ? TimeOfDay(date: item.start) + item.durationMinutes
            : TimeOfDay(date: item.start)
        translation = 0
        isDragging = true
        // Measure the anchor on the drag scale, including compact break minutes.
        anchorY = scale(items, draft: item).yOffset(for: time)
    }

    /// Return a scroll correction so a scale change does not move the card away from the finger.
    @discardableResult
    func update(_ draft: inout TimelineItem, translation: CGFloat, items: [TimelineItem]) -> CGFloat
    {
        // A tap can reopen label or patient selection. Keep stored times exact until movement.
        guard isDragging, original?.id == draft.id,
            translation != 0 || self.translation != 0
        else { return 0 }
        dragCooldown.record()
        self.translation = translation
        let oldScale = scale(items, draft: draft)
        updateDraft(&draft, scale: oldScale)
        let y = anchorY + translation
        let breakY = oldScale.yOffset(for: Bitehaus.break.start)
        let overBreak = y >= breakY && y < breakY + oldScale.breakHeight
        if !oldScale.isBreakExpanded && overBreak {
            if hoverRequest == nil { hoverRequest = UUID() }
        } else {
            hoverRequest = nil
        }
        if expanded, !overBreak,
            !(Bitehaus.break.start..<Bitehaus.break.end).contains(TimeOfDay(date: draft.start))
        {
            expanded = false
            return rebase(from: oldScale, draft: draft, items: items)
        }
        return 0
    }

    func expandBreak(draft: TimelineItem, items: [TimelineItem]) -> CGFloat {
        guard isDragging, hoverRequest != nil else { return 0 }
        let oldScale = scale(items, draft: draft)
        expanded = true
        hoverRequest = nil
        return rebase(from: oldScale, draft: draft, items: items)
    }

    func release() {
        if isDragging {
            dragCooldown.record()
        }
        isDragging = false
        hoverRequest = nil
        original = nil
    }

    private func rebase(from oldScale: TimelineScale, draft: TimelineItem, items: [TimelineItem])
        -> CGFloat
    {
        let time =
            edge == .duration
            ? TimeOfDay(date: draft.start) + draft.durationMinutes
            : TimeOfDay(date: draft.start)
        let delta = scale(items, draft: draft).yOffset(for: time) - oldScale.yOffset(for: time)
        anchorY += delta
        return delta
    }

    private func updateDraft(_ draft: inout TimelineItem, scale: TimelineScale) {
        guard let original else { return }
        let proposed = scale.time(at: anchorY + translation).totalMinutes
        let snapped = Int((Double(proposed) / 5).rounded()) * 5
        let originalStart = TimeOfDay(date: original.start).totalMinutes
        let start: Int
        let end: Int
        switch edge {
        case .move:
            start = min(
                max(snapped, Bitehaus.opening.totalMinutes),
                Bitehaus.closing.totalMinutes - original.durationMinutes)
            end = start + original.durationMinutes
        case .duration:
            start = originalStart
            end = min(max(snapped, originalStart + 15), Bitehaus.closing.totalMinutes)
        }
        draft = draft.rescheduled(
            start: TimeOfDay(start / 60, start % 60).on(date: original.start),
            durationMinutes: end - start)
    }
}
