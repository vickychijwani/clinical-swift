import ClinicalModels
import Dependencies
import Foundation
import Observation

/// Gesture release and date selection change only the preview in memory.
/// The editor owns saving and errors.
@MainActor @Observable
final class TimelineAdjustment {
    enum Edge { case move, duration }

    @ObservationIgnored @Dependency(\.calendar) private var calendar
    private(set) var original: TimelineItem?
    private(set) var preview: TimelineItem?
    private(set) var edge: Edge = .move
    private(set) var isDragging = false
    private(set) var hoverRequest: UUID?
    private var expanded = false
    private var anchorY: CGFloat = 0
    private var translation: CGFloat = 0

    private(set) var selectedID: TimelineItem.ID?

    var isActive: Bool { preview != nil }

    func select(_ item: TimelineItem) {
        guard !isDragging else { return }
        preview = item
        selectedID = item.id
    }

    func items(_ items: [TimelineItem], on date: Date? = nil) -> [TimelineItem] {
        guard let preview else { return items }
        let date = date ?? items.first?.start ?? preview.start
        var items = items.filter { $0.id != preview.id }
        if calendar.isDate(preview.start, inSameDayAs: date) {
            items.append(preview)
        }
        return items
    }

    func scale(_ items: [TimelineItem], on date: Date? = nil) -> TimelineScale {
        let displayed = self.items(items, on: date)
        guard isDragging,
            displayed.contains(where: { $0.id == preview?.id })
        else { return TimelineScale(items: displayed) }
        let others = displayed.filter { $0.id != preview?.id }
        return TimelineScale(
            items: others,
            breakPresentation: expanded || TimelineScale(items: others).isBreakExpanded
                ? .expanded : .compact
        )
    }

    func begin(_ item: TimelineItem, edge: Edge, items: [TimelineItem]) {
        guard !isDragging,
            item.allowsAdjustment,
            selectedID == nil || selectedID == item.id
        else { return }
        let item = preview ?? item
        original = item
        preview = item
        selectedID = item.id
        self.edge = edge
        expanded = TimelineScale(items: items).isBreakExpanded
        let time =
            edge == .duration
            ? TimeOfDay(date: item.start, calendar: calendar) + item.durationMinutes
            : TimeOfDay(date: item.start, calendar: calendar)
        anchorY = scale(items).yOffset(for: time)
        translation = 0
        isDragging = true
    }

    /// Return a scroll correction so a scale change does not move the card away from the finger.
    @discardableResult
    func update(translation: CGFloat, items: [TimelineItem]) -> CGFloat {
        // A tap can reopen label or patient selection. Keep stored times exact until movement.
        guard isDragging, translation != 0 || self.translation != 0 else { return 0 }
        self.translation = translation
        let oldScale = scale(items)
        updatePreview(scale: oldScale)
        let y = anchorY + translation
        let breakY = oldScale.yOffset(for: Bitehaus.break.start)
        let overBreak = y >= breakY && y < breakY + oldScale.breakHeight
        if !oldScale.isBreakExpanded && overBreak {
            if hoverRequest == nil { hoverRequest = UUID() }
        } else {
            hoverRequest = nil
        }
        if expanded, !overBreak, let preview,
            !(Bitehaus.break.start..<Bitehaus.break.end).contains(
                TimeOfDay(date: preview.start, calendar: calendar))
        {
            expanded = false
            return rebase(from: oldScale, items: items)
        }
        return 0
    }

    func expandBreak(items: [TimelineItem]) -> CGFloat {
        guard isDragging, hoverRequest != nil else { return 0 }
        let oldScale = scale(items)
        expanded = true
        hoverRequest = nil
        return rebase(from: oldScale, items: items)
    }

    func release() {
        isDragging = false
        hoverRequest = nil
        original = nil
    }

    func finish() {
        preview = nil
        original = nil
        isDragging = false
        hoverRequest = nil
        selectedID = nil
    }

    func selectDate(_ date: Date) -> TimelineItem? {
        guard let preview,
            !calendar.isDate(preview.start, inSameDayAs: date)
        else { return nil }
        self.preview = preview.rescheduled(
            start: TimeOfDay(date: preview.start, calendar: calendar).on(
                date: date, using: calendar),
            durationMinutes: preview.durationMinutes)
        hoverRequest = nil
        isDragging = false
        return self.preview
    }

    private func rebase(from oldScale: TimelineScale, items: [TimelineItem]) -> CGFloat {
        guard let preview else { return 0 }
        let time =
            edge == .duration
            ? TimeOfDay(date: preview.start, calendar: calendar) + preview.durationMinutes
            : TimeOfDay(date: preview.start, calendar: calendar)
        let delta = scale(items).yOffset(for: time) - oldScale.yOffset(for: time)
        anchorY += delta
        return delta
    }

    private func updatePreview(scale: TimelineScale) {
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
        preview = original.rescheduled(
            start: TimeOfDay(start / 60, start % 60).on(date: original.start, using: calendar),
            durationMinutes: end - start)
    }
}
