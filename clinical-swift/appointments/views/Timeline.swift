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
    var onSelectActiveItem: () -> Void = {}
    var allowsAdjustment = false
    var onDraggingChanged: (Bool) -> Void = { _ in }
    var onScaleChange: (CGFloat) -> Void = { _ in }
    var onBeginBooking: (TimeOfDay) -> TimelineAdjustment? = { _ in nil }
    var onBookingRelease: (TimelineAdjustment) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onDiscard: () -> Void = {}
    var onDone: @MainActor () async -> Void = {}
    var onDelete: (@MainActor () async -> Void)? = nil

    var date: Date = .now
    // The session owns this reference. View state would keep the previous session's adjustment.
    var adjustment: TimelineAdjustment?
    var isWorking = false
    @State private var lastDragEnd: ContinuousClock.Instant?
    @State private var touchStart: CGPoint?
    // Keep the first touch attached while Schedule installs the new booking session.
    @State private var bookingDrag: TimelineAdjustment?

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
        .task(id: adjustment?.hoverRequest) {
            guard let adjustment, adjustment.hoverRequest != nil,
                adjustment.preview?.start.isSameDayAs(date) == true
            else { return }
            do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            withAnimation(.smooth(duration: 0.22)) {
                onScaleChange(adjustment.expandBreak(items: items))
            }
        }
        .onChange(of: adjustment?.isDragging) { _, dragging in
            if dragging != true {
                bookingDrag = nil
                touchStart = nil
            }
            onDraggingChanged(dragging == true)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: adjustment?.isDragging == true)
        .sensoryFeedback(.selection, trigger: adjustment?.preview?.start)
        .sensoryFeedback(.selection, trigger: adjustment?.preview?.durationMinutes)
    }

    private func timelineContent(now: Date?) -> some View {
        let scale = allowsAdjustment ? adjustment?.scale(items, on: date) ?? scale : scale
        return GeometryReader { geometry in
            let engine = TimelineLayoutEngine(
                availableWidth: geometry.size.width,
                scale: scale
            )
            let layouts = engine.layout(
                items: adjustment?.items(items, on: date) ?? items,
                floatingID: adjustment?.selectedID)

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
                    let selected = isSelected(layout.item)
                    TimelineItemView(
                        item: layout.item,
                        size: layout.rect.size,
                        isSelected: selected,
                        isDeemphasized: adjustment?.isActive == true && !selected,
                        interactionsEnabled: !isWorking
                            && (itemInteractionsEnabled || (allowsAdjustment && selected)),
                        showsAdjustmentControls: selected && allowsAdjustment,
                        isDragging: adjustment?.isDragging == true,
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
                    .zIndex(selected ? 1 : 0)
                    .position(x: layout.rect.midX, y: layout.rect.midY)
                }

                if let nowY = nowY(for: now) {
                    NowMarkerView(availableWidth: geometry.size.width)
                        .position(x: geometry.size.width / 2, y: nowY)
                        .zIndex(2)
                }
            }
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        touchStart = value.startLocation
                        if let bookingDrag {
                            onScaleChange(
                                bookingDrag.update(
                                    translation: value.translation.height, items: items))
                        }
                    }
                    .onEnded { value in
                        touchStart = nil
                        guard let bookingDrag else { return }
                        self.bookingDrag = nil
                        // Done or Cancel can end the drag before the finger lifts.
                        guard bookingDrag.isDragging else { return }
                        lastDragEnd = .now
                        onScaleChange(
                            bookingDrag.update(
                                translation: value.translation.height, items: items))
                        bookingDrag.release()
                        onBookingRelease(bookingDrag)
                    },
                including: allowsAdjustment && (adjustment?.isActive != true || bookingDrag != nil)
                    ? .all : .subviews
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in
                        guard allowsAdjustment, itemInteractionsEnabled,
                            adjustment?.isActive != true,
                            let touchStart
                        else { return }
                        let y = touchStart.y - geometry.frame(in: .global).minY
                        // Use the displayed scale, including a compact break, for touch mapping.
                        bookingDrag = onBeginBooking(scale.time(at: y))
                    },
                including: allowsAdjustment && (adjustment?.isActive != true || bookingDrag != nil)
                    ? .all : .subviews
            )
        }
        .frame(height: scale.totalHeight)
        .padding(.vertical, Timeline.metrics.verticalPadding)
    }

    private func isSelected(_ item: TimelineItem) -> Bool {
        guard let id = adjustment?.selectedID else { return false }
        return item.id == id
    }

    private func selectItem(_ item: TimelineItem) {
        // A hold can finish in the same event as the button release.
        guard adjustment?.isActive != true,
            lastDragEnd.map({ $0.duration(to: .now) > .milliseconds(150) }) ?? true
        else { return }
        onSelectItem(item)
    }

    private func move(_ item: TimelineItem, value: DragGesture.Value) {
        if abs(value.translation.height) > 10 || abs(value.translation.width) > 10 {
            lastDragEnd = .now
        }
        guard let adjustment, !isWorking, isSelected(item) else { return }
        if !adjustment.isDragging {
            adjustment.begin(item, edge: .move, items: items)
        }
        if adjustment.isDragging, adjustment.edge == .move {
            onScaleChange(adjustment.update(translation: value.translation.height, items: items))
        }
    }

    private func endMove(_ item: TimelineItem, value: DragGesture.Value) {
        guard let adjustment else { return }
        if abs(value.translation.height) > 10 || abs(value.translation.width) > 10 {
            lastDragEnd = .now
        }
        guard isSelected(item), adjustment.isDragging, adjustment.edge == .move else { return }
        onScaleChange(adjustment.update(translation: value.translation.height, items: items))
        releaseAdjustment()
        if abs(value.translation.height) < 5, abs(value.translation.width) < 5 {
            onSelectActiveItem()
        }
    }

    private func drag(
        _ item: TimelineItem, edge: TimelineAdjustment.Edge, value: DragGesture.Value
    ) {
        guard let adjustment, !isWorking else { return }
        if !adjustment.isDragging { adjustment.begin(item, edge: edge, items: items) }
        onScaleChange(adjustment.update(translation: value.translation.height, items: items))
    }

    private func releaseAdjustment() {
        guard let adjustment, adjustment.isDragging else { return }
        lastDragEnd = .now
        adjustment.release()
    }

    private func nowY(for now: Date?) -> CGFloat? {
        guard let now else {
            return nil
        }

        let time = now.timeOfDay
        let scale = allowsAdjustment ? adjustment?.scale(items, on: date) ?? scale : scale
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
    .background(Color("AppBackground"))
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
