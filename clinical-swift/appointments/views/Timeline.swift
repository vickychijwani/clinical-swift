import ClinicalModels
import SwiftUI

struct Timeline: View {
    let items: [TimelineItem]
    let scale: TimelineScale

    /// Properties for rendering the "Now" marker line.
    let showsNowMarker: Bool
    var previewNowMarker: Date? = nil
    var itemInteractionsEnabled = true
    var onSelectItem: (TimelineItem) -> Void = { _ in }
    var onSelectDraft: () -> Void = {}
    var allowsAdjustment = false
    var onDraggingChanged: (Bool) -> Void = { _ in }
    var onScaleChange: (CGFloat) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onDiscard: () -> Void = {}
    var onDone: @MainActor () async -> Void = {}
    var onDelete: (@MainActor () async -> Void)? = nil

    var date: Date = .now
    // The parent supplies the session. View state would keep the previous editor's draft.
    var editorSession: ScheduleEditorSession?
    var isWorking = false
    @State private var lastDragEnd: ContinuousClock.Instant?

    static let metrics = TimelineMetrics(
        hourHeight: 60,
        timeColumnWidth: 40,
        verticalPadding: 8,
        horizontalCardMargin: 12,
        verticalCardMargin: 0,
        overlapColumnSpacing: 0,
        compactBreakHeight: 32
    )

    var body: some View {
        Group {
            if let previewNowMarker {
                timelineContent(now: previewNowMarker)
            } else if showsNowMarker {
                // Update every 1 minute.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    timelineContent(now: context.date)
                }
            } else {
                timelineContent(now: nil)
            }
        }
        .task(id: editorSession?.adjustment.hoverRequest) {
            guard let editorSession, editorSession.adjustment.hoverRequest != nil,
                editorSession.preview.start.isSameDayAs(date)
            else { return }
            do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            withAnimation(.smooth(duration: 0.22)) {
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

    private func timelineContent(now: Date?) -> some View {
        let scale = allowsAdjustment ? editorSession?.scale(items, on: date) ?? scale : scale
        return GeometryReader { geometry in
            let engine = TimelineLayoutEngine(
                availableWidth: geometry.size.width,
                scale: scale
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
                    TimelineItemView(
                        item: layout.item,
                        size: layout.rect.size,
                        isDraft: draft,
                        isDeemphasized: editorSession != nil && !draft,
                        interactionsEnabled: !isWorking
                            && (itemInteractionsEnabled || (allowsAdjustment && draft)),
                        showsAdjustmentControls: draft && allowsAdjustment,
                        isDragging: editorSession?.adjustment.isDragging == true,
                        isWorking: isWorking,
                        onSelect: { selectItem(layout.item) },
                        onMoveChanged: { move(layout.item, value: $0) },
                        onMoveEnded: { endMove(layout.item, value: $0) },
                        onResizeChanged: { drag(layout.item, edge: .duration, value: $0) },
                        onResizeEnded: releaseAdjustment,
                        onCancel: onCancel,
                        onDiscard: onDiscard,
                        onDone: onDone,
                        onDelete: onDelete
                    )
                    .zIndex(draft ? 1 : 0)
                    .position(x: layout.rect.midX, y: layout.rect.midY)
                }

                if let nowY = nowY(for: now) {
                    NowMarkerView(availableWidth: geometry.size.width)
                        .position(x: geometry.size.width / 2, y: nowY)
                        .zIndex(2)
                }
            }
        }
        .frame(height: scale.totalHeight)
        .padding(.vertical, Timeline.metrics.verticalPadding)
    }

    private func isDraft(_ item: TimelineItem) -> Bool {
        guard let id = editorSession?.preview.id else { return false }
        return item.id == id
    }

    private func selectItem(_ item: TimelineItem) {
        // A move can finish in the same event as the button release.
        guard lastDragEnd.map({ $0.duration(to: .now) > .milliseconds(150) }) ?? true
        else { return }
        if isDraft(item) {
            onSelectDraft()
            return
        }
        guard editorSession == nil else { return }
        onSelectItem(item)
    }

    private func move(_ item: TimelineItem, value: DragGesture.Value) {
        lastDragEnd = .now
        guard let editorSession, !isWorking, isDraft(item) else { return }
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
        lastDragEnd = .now
        guard isDraft(item), adjustment.isDragging, adjustment.edge == .move else { return }
        onScaleChange(
            editorSession.updateAdjustment(translation: value.translation.height, items: items))
        releaseAdjustment()
    }

    private func drag(
        _ item: TimelineItem, edge: TimelineAdjustment.Edge, value: DragGesture.Value
    ) {
        guard let editorSession, !isWorking else { return }
        if !editorSession.adjustment.isDragging {
            editorSession.beginAdjustment(item, edge: edge, items: items)
        }
        onScaleChange(
            editorSession.updateAdjustment(translation: value.translation.height, items: items))
    }

    private func releaseAdjustment() {
        guard let adjustment = editorSession?.adjustment, adjustment.isDragging else { return }
        lastDragEnd = .now
        adjustment.release()
    }

    private func nowY(for now: Date?) -> CGFloat? {
        guard let now else {
            return nil
        }

        let time = now.timeOfDay
        let scale = allowsAdjustment ? editorSession?.scale(items, on: date) ?? scale : scale
        guard scale.showsTime(time) else {
            return nil
        }

        return scale.yOffset(for: time)
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
        previewNowMarker: Date.now.setTime(9, 30)
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
