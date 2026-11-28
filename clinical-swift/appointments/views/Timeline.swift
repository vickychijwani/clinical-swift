import ClinicalModels
import SwiftUI

struct Timeline: View {
    @Environment(\.scheduleCardTuning) private var cardTuning

    let items: [TimelineItem]
    let scale: TimelineScale

    /// Properties for rendering the "Now" marker line.
    let showsNowMarker: Bool
    var previewNowMarker: Date? = nil
    var itemInteractionsEnabled = true
    var selectedAppointmentID: Appointment.ID? = nil
    var canSelect: () -> Bool = { true }
    var onSelectItem: (TimelineItem) -> Void = { _ in }
    var allowsAdjustment = false
    var onDraggingChanged: (Bool) -> Void = { _ in }
    var onScaleChange: (CGFloat) -> Void = { _ in }

    let date: Date
    // The parent supplies the session. View state would keep the previous editor's draft.
    var editorSession: ScheduleEditorSession?

    static let metrics = TimelineMetrics.standard

    var body: some View {
        let scale = allowsAdjustment ? editorSession?.scale(items, on: date) ?? scale : scale

        GeometryReader { geometry in
            let engine = TimelineLayoutEngine(
                availableWidth: geometry.size.width,
                scale: scale,
                overlap: cardTuning.overlap
            )
            let layouts = engine.layout(
                items: items,
                floatingID: editorSession?.preview.id)

            ZStack(alignment: .topLeading) {
                TimelineBreakView(
                    scale: scale,
                    availableWidth: geometry.size.width
                )

                TimelineHourGrid(
                    scale: scale,
                    availableWidth: geometry.size.width
                )

                ForEach(layouts) { layout in
                    let draft = isDraft(layout.item)
                    let selected = editorSession == nil && !draft && isSelected(layout.item)
                    let isWorking = editorSession?.isWorking == true
                    TimelineItemView(
                        item: layout.item,
                        size: layout.rect.size,
                        contentTrailingInset: layout.contentTrailingInset,
                        isOverlappingFront: layout.isOverlappingFront,
                        presentation: layout.presentation,
                        isDraft: draft,
                        isSelected: selected,
                        isDeemphasized: editorSession != nil && !draft,
                        interactionsEnabled: !isWorking
                            && (itemInteractionsEnabled || (allowsAdjustment && draft)),
                        adjustmentControls: adjustmentControls(for: layout.item, isDraft: draft),
                        onSelect: { selectItem(layout.item) }
                    )
                    .zIndex(Self.itemZIndex(for: layout, isDraft: draft, itemCount: layouts.count))
                    .position(x: layout.rect.midX, y: layout.rect.midY)
                }

                if previewNowMarker != nil || showsNowMarker {
                    TimelineNowMarkerOverlay(
                        availableWidth: geometry.size.width,
                        scale: scale,
                        previewNowMarker: previewNowMarker
                    )
                    .zIndex(Double(layouts.count + 2))
                }
            }
        }
        .frame(height: scale.totalHeight)
        .padding(.vertical, scale.metrics.verticalPadding)
        .task(id: editorSession?.adjustment.hoverRequest) {
            guard let editorSession, editorSession.adjustment.hoverRequest != nil,
                editorSession.preview.start.isSameDayAs(date)
            else { return }
            do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            withAnimation(AppMotion.animation(.smooth(duration: 0.22))) {
                onScaleChange(editorSession.expandBreak(items: items))
            }
        }
        .onChange(of: editorSession?.adjustment.isDragging) { _, dragging in
            onDraggingChanged(dragging == true)
        }
        .sensoryFeedback(
            .impact(weight: .light), trigger: editorSession?.adjustment.isDragging == true
        )
        .sensoryFeedback(.selection, trigger: editorSession?.preview.start)
        .sensoryFeedback(.selection, trigger: editorSession?.preview.durationMinutes)
    }

    static func itemZIndex(
        for layout: TimelineItemLayoutInfo,
        isDraft: Bool,
        itemCount: Int
    ) -> Double {
        isDraft ? Double(itemCount + 1) : Double(layout.zIndex)
    }

    private func adjustmentControls(
        for item: TimelineItem, isDraft: Bool
    ) -> TimelineItemView.AdjustmentControls? {
        guard isDraft, allowsAdjustment, let editorSession else { return nil }
        @MainActor func saveDraft() async { _ = await editorSession.save() }
        @MainActor func deleteDraft() async { _ = await editorSession.delete() }
        return TimelineItemView.AdjustmentControls(
            isDragging: editorSession.adjustment.isDragging,
            isWorking: editorSession.isWorking,
            onMoveChanged: { move(item, value: $0) },
            onMoveEnded: { endMove(item, value: $0) },
            onResizeChanged: { drag(item, edge: .duration, value: $0) },
            onResizeEnded: releaseAdjustment,
            onCancel: { editorSession.adjustment.release() },
            onDiscard: { editorSession.discard() },
            onDone: saveDraft,
            onDelete: editorSession.canDelete ? deleteDraft : nil
        )
    }

    private func isDraft(_ item: TimelineItem) -> Bool {
        guard let id = editorSession?.preview.id else { return false }
        return item.id == id
    }

    private func isSelected(_ item: TimelineItem) -> Bool {
        guard let selectedAppointmentID, case .appointment(let appointment) = item else {
            return false
        }
        return appointment.id == selectedAppointmentID
    }

    private func selectItem(_ item: TimelineItem) {
        // A move can finish in the same event as the button release.
        guard canSelect(), editorSession?.adjustment.allowsSelection != false else { return }
        if isDraft(item) {
            editorSession?.isShowingSheet = true
            return
        }
        guard editorSession == nil else { return }
        onSelectItem(item)
    }

    private func move(_ item: TimelineItem, value: DragGesture.Value) {
        guard let editorSession, !editorSession.isWorking, isDraft(item) else { return }
        let adjustment = editorSession.adjustment
        if !adjustment.isDragging {
            editorSession.beginAdjustment(item, edge: .move, items: items)
        }
        if adjustment.isDragging, adjustment.edge == .move {
            onScaleChange(
                editorSession.updateAdjustment(translation: value.translation.height, items: items))
        }
    }

    private func endMove(_ item: TimelineItem, value: DragGesture.Value) {
        guard let editorSession else { return }
        let adjustment = editorSession.adjustment
        guard isDraft(item), adjustment.isDragging, adjustment.edge == .move else { return }
        onScaleChange(
            editorSession.updateAdjustment(translation: value.translation.height, items: items))
        releaseAdjustment()
    }

    private func drag(
        _ item: TimelineItem, edge: TimelineAdjustment.Edge, value: DragGesture.Value
    ) {
        guard let editorSession, !editorSession.isWorking else { return }
        if !editorSession.adjustment.isDragging {
            editorSession.beginAdjustment(item, edge: edge, items: items)
        }
        onScaleChange(
            editorSession.updateAdjustment(translation: value.translation.height, items: items))
    }

    private func releaseAdjustment() {
        guard let adjustment = editorSession?.adjustment, adjustment.isDragging else { return }
        adjustment.release()
    }

    static func nowY(for now: Date, scale: TimelineScale) -> CGFloat? {
        let time = now.timeOfDay
        guard scale.showsTime(time) else {
            return nil
        }

        return scale.yOffset(for: time)
    }
}

private struct TimelineNowMarkerOverlay: View {
    let availableWidth: CGFloat
    let scale: TimelineScale
    let previewNowMarker: Date?

    var body: some View {
        if let previewNowMarker {
            marker(at: previewNowMarker)
        } else {
            // Update on minute boundaries so the time badge stays in sync with the clock.
            TimelineView(.everyMinute) { context in
                marker(at: context.date)
            }
        }
    }

    @ViewBuilder
    private func marker(at now: Date) -> some View {
        if let nowY = Timeline.nowY(for: now, scale: scale) {
            NowMarkerView(
                availableWidth: availableWidth,
                metrics: scale.metrics,
                indicator: .time(now)
            )
            .position(x: availableWidth / 2, y: nowY)
        }
    }
}

func sampleTimeline(
    items: [TimelineItem] = sampleAppointments.map(TimelineItem.appointment)
) -> some View {
    let scale = TimelineScale(items: items)

    return Timeline(
        items: items,
        scale: scale,
        showsNowMarker: true,
        previewNowMarker: Date.now.setTime(9, 30),
        date: ClinicDate.today
    )
    .background(AppColor.canvas)
}

#Preview {
    sampleTimeline()
}

#Preview("Expanded break") {
    sampleTimeline(
        items: sampleAppointments.map(TimelineItem.appointment) + [
            .appointment(
                Appointment(
                    patientName: "Draft appointment",
                    start: Date.now.setTime(14, 0),
                    durationMinutes: 45,
                    status: .draft
                )
            )
        ]
    )
}
