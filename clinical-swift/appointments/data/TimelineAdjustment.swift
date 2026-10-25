import ClinicalModels
import Dependencies
import Foundation
import Observation

/// One schedule session owns the preview. Release and date selection write its time;
/// Done ends the session without opening appointment details.
@MainActor @Observable
final class TimelineAdjustment {
    enum Edge { case move, start, end }

    @ObservationIgnored @Dependency(\.calendar) private var calendar
    private(set) var original: Appointment?
    private(set) var preview: Appointment?
    private(set) var edge: Edge = .move
    private(set) var isDragging = false
    private(set) var isSaving = false
    private(set) var hoverRequest: UUID?
    private var expanded = false
    private var anchorY: CGFloat = 0
    private var translation: CGFloat = 0

    private(set) var selectedID: Appointment.ID?
    var errorMessage: String?

    var isActive: Bool { preview != nil }

    func items(_ items: [TimelineItem], on date: Date? = nil) -> [TimelineItem] {
        guard let preview else { return items }
        let date = date ?? items.first?.start ?? preview.start
        var items = items.filter { $0.id != .appointment(preview.id) }
        if calendar.isDate(preview.start, inSameDayAs: date) {
            items.append(.appointment(preview))
        }
        return items
    }

    func scale(_ items: [TimelineItem], on date: Date? = nil) -> TimelineScale {
        let displayed = self.items(items, on: date)
        guard isDragging,
            displayed.contains(where: { $0.id == preview.map { .appointment($0.id) } })
        else { return TimelineScale(items: displayed) }
        let others = displayed.filter { $0.id != preview.map { .appointment($0.id) } }
        return TimelineScale(
            items: others,
            breakPresentation: expanded || TimelineScale(items: others).isBreakExpanded
                ? .expanded : .compact
        )
    }

    func begin(_ appointment: Appointment, edge: Edge, items: [TimelineItem]) {
        guard !isDragging, !isSaving, appointment.status == .scheduled,
            selectedID == nil || selectedID == appointment.id
        else { return }
        let appointment = preview ?? appointment
        original = appointment
        preview = appointment
        selectedID = appointment.id
        self.edge = edge
        expanded = TimelineScale(items: items).isBreakExpanded
        let time =
            edge == .end
            ? appointment.start.timeOfDay + appointment.durationMinutes
            : appointment.start.timeOfDay
        anchorY = scale(items).yOffset(for: time)
        translation = 0
        isDragging = true
    }

    /// Return a scroll correction so a scale change does not move the card away from the finger.
    @discardableResult
    func update(translation: CGFloat, items: [TimelineItem]) -> CGFloat {
        guard isDragging else { return 0 }
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
            !(Bitehaus.break.start..<Bitehaus.break.end).contains(preview.start.timeOfDay)
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

    func release() -> Appointment? {
        isDragging = false
        hoverRequest = nil
        guard let preview, let original,
            preview.start != original.start || preview.durationMinutes != original.durationMinutes
        else {
            original = nil
            return nil
        }
        isSaving = true
        return preview
    }

    func finish() {
        preview = nil
        original = nil
        isDragging = false
        isSaving = false
        hoverRequest = nil
        selectedID = nil
    }

    func didSave() {
        isSaving = false
        original = nil
    }

    func selectDate(_ date: Date) -> Appointment? {
        guard let preview, !calendar.isDate(preview.start, inSameDayAs: date) else { return nil }
        self.preview = Appointment(
            id: preview.id, patientName: preview.patientName,
            start: TimeOfDay(date: preview.start, calendar: calendar).on(
                date: date, using: calendar),
            durationMinutes: preview.durationMinutes, status: preview.status)
        hoverRequest = nil
        isDragging = false
        isSaving = true
        return self.preview
    }

    private func rebase(from oldScale: TimelineScale, items: [TimelineItem]) -> CGFloat {
        guard let preview else { return 0 }
        let time =
            edge == .end
            ? preview.start.timeOfDay + preview.durationMinutes
            : preview.start.timeOfDay
        let delta = scale(items).yOffset(for: time) - oldScale.yOffset(for: time)
        anchorY += delta
        return delta
    }

    private func updatePreview(scale: TimelineScale) {
        guard let original else { return }
        let proposed = scale.time(at: anchorY + translation).totalMinutes
        let snapped = Int((Double(proposed) / 5).rounded()) * 5
        let originalStart = original.start.timeOfDay.totalMinutes
        let originalEnd = originalStart + original.durationMinutes
        let start: Int
        let end: Int
        switch edge {
        case .move:
            start = min(
                max(snapped, Bitehaus.opening.totalMinutes),
                Bitehaus.closing.totalMinutes - original.durationMinutes)
            end = start + original.durationMinutes
        case .start:
            start = min(max(snapped, Bitehaus.opening.totalMinutes), originalEnd - 5)
            end = originalEnd
        case .end:
            start = originalStart
            end = min(max(snapped, originalStart + 5), Bitehaus.closing.totalMinutes)
        }
        preview = Appointment(
            id: original.id, patientName: original.patientName,
            start: TimeOfDay(start / 60, start % 60).on(date: original.start, using: calendar),
            durationMinutes: end - start, status: original.status)
    }
}
