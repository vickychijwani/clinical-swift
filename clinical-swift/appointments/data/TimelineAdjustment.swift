import ClinicalModels
import Dependencies
import Foundation
import Observation

/// Gestures change only the editor's draft in memory.
/// The editor owns saving and errors.
@MainActor @Observable
final class TimelineAdjustment {
    enum Edge { case move, duration }

    @ObservationIgnored @Dependency(\.calendar) private var calendar
    private(set) var original: TimelineItem?
    private(set) var edge: Edge = .move
    private(set) var isDragging = false
    private(set) var hoverRequest: UUID?
    private var expanded = false
    private var anchorY: CGFloat = 0
    private var translation: CGFloat = 0

    func items(_ items: [TimelineItem], draft: TimelineItem, on date: Date? = nil) -> [TimelineItem]
    {
        let date = date ?? items.first?.start ?? draft.start
        var items = items.filter { $0.id != draft.id }
        if calendar.isDate(draft.start, inSameDayAs: date) {
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
        original = item
        self.edge = edge
        expanded = TimelineScale(items: items).isBreakExpanded
        let time =
            edge == .duration
            ? TimeOfDay(date: item.start, calendar: calendar) + item.durationMinutes
            : TimeOfDay(date: item.start, calendar: calendar)
        anchorY = scale(items, draft: item).yOffset(for: time)
        translation = 0
        isDragging = true
    }

    /// Return a scroll correction so a scale change does not move the card away from the finger.
    @discardableResult
    func update(_ draft: inout TimelineItem, translation: CGFloat, items: [TimelineItem]) -> CGFloat
    {
        // A tap can reopen label or patient selection. Keep stored times exact until movement.
        guard isDragging, original?.id == draft.id,
            translation != 0 || self.translation != 0
        else { return 0 }
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
            !(Bitehaus.break.start..<Bitehaus.break.end).contains(
                TimeOfDay(date: draft.start, calendar: calendar))
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
        isDragging = false
        hoverRequest = nil
        original = nil
    }

    private func rebase(from oldScale: TimelineScale, draft: TimelineItem, items: [TimelineItem])
        -> CGFloat
    {
        let time =
            edge == .duration
            ? TimeOfDay(date: draft.start, calendar: calendar) + draft.durationMinutes
            : TimeOfDay(date: draft.start, calendar: calendar)
        let delta = scale(items, draft: draft).yOffset(for: time) - oldScale.yOffset(for: time)
        anchorY += delta
        return delta
    }

    private func updateDraft(_ draft: inout TimelineItem, scale: TimelineScale) {
        guard let original else { return }
        let proposed = scale.time(at: anchorY + translation).totalMinutes
        let snapped = Int((Double(proposed) / 5).rounded()) * 5
        let originalStart = TimeOfDay(date: original.start, calendar: calendar).totalMinutes
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
            start: TimeOfDay(start / 60, start % 60).on(date: original.start, using: calendar),
            durationMinutes: end - start)
    }
}
