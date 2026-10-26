import ClinicalModels
import Dependencies
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
    var adjustment = TimelineAdjustment()
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
        .task(id: adjustment.hoverRequest) {
            guard adjustment.hoverRequest != nil,
                adjustment.preview?.start.isSameDayAs(date) == true
            else { return }
            do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            withAnimation(.smooth(duration: 0.22)) {
                onScaleChange(adjustment.expandBreak(items: items))
            }
        }
        .onChange(of: adjustment.isDragging) { _, dragging in
            if !dragging {
                bookingDrag = nil
                touchStart = nil
            }
            onDraggingChanged(dragging)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: adjustment.isDragging)
        .sensoryFeedback(.selection, trigger: adjustment.preview?.start)
        .sensoryFeedback(.selection, trigger: adjustment.preview?.durationMinutes)
    }

    private func timelineContent(now: Date?) -> some View {
        let scale = allowsAdjustment ? adjustment.scale(items, on: date) : scale
        return GeometryReader { geometry in
            let engine = TimelineLayoutEngine(
                availableWidth: geometry.size.width,
                scale: scale
            )
            let layouts = engine.layout(
                items: adjustment.items(items, on: date),
                floatingID: adjustment.selectedID)

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
                    Button {
                        // A hold can finish in the same event as the button release.
                        guard !adjustment.isActive,
                            lastDragEnd.map({ $0.duration(to: .now) > .milliseconds(150) }) ?? true
                        else { return }
                        onSelectItem(layout.item)
                    } label: {
                        ScheduleItemCard(
                            item: layout.item,
                            isAdjusting: isSelected(layout.item),
                            isDeemphasized: adjustment.isActive && !isSelected(layout.item)
                        )
                        .frame(width: layout.rect.width, height: layout.rect.height)
                        // Keep clipped text within the card's tap area.
                        // Regression tests: testLongNameDoesNotStealTapFromRightAppointment()
                        // and testMixedThreeColumnCardsKeepSeparateTapAreas().
                        .contentShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
                        .clipShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
                        .overlay {
                            if case .appointment = layout.item {
                                RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
                                    .strokeBorder(AppColor.grid)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .buttonStyle(TimelineCardButtonStyle())
                    .allowsHitTesting(
                        !adjustment.isSaving
                            && (itemInteractionsEnabled
                                || (allowsAdjustment && isSelected(layout.item)))
                    )
                    // UI tests use the item type and ID to select each card.
                    .accessibilityIdentifier(layout.item.id.sortKey)
                    .accessibilityValue("\(layout.item.durationMinutes) min")
                    .simultaneousGesture(
                        // Measure from touch-down so the hold does not lose the first movement.
                        // A swipe must cancel selection even when the day is too short to scroll.
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if abs(value.translation.height) > 10
                                    || abs(value.translation.width) > 10
                                {
                                    lastDragEnd = .now
                                }
                                if isSelected(layout.item), !adjustment.isDragging {
                                    adjustment.begin(layout.item, edge: .move, items: items)
                                }
                                if isSelected(layout.item), adjustment.isDragging,
                                    adjustment.edge == .move
                                {
                                    onScaleChange(
                                        adjustment.update(
                                            translation: value.translation.height, items: items))
                                }
                            }
                            .onEnded { value in
                                if abs(value.translation.height) > 10
                                    || abs(value.translation.width) > 10
                                {
                                    lastDragEnd = .now
                                }
                                if isSelected(layout.item), adjustment.isDragging,
                                    adjustment.edge == .move
                                {
                                    onScaleChange(
                                        adjustment.update(
                                            translation: value.translation.height, items: items))
                                    releaseAdjustment()
                                    if abs(value.translation.height) < 5,
                                        abs(value.translation.width) < 5
                                    {
                                        onSelectActiveItem()
                                    }
                                }
                            }
                    )
                    .overlay {
                        // Handles sit outside the body gesture so a resize cannot start a move.
                        if isSelected(layout.item),
                            allowsAdjustment,
                            layout.item.allowsAdjustment
                        {
                            TimelineAdjustmentHandles(
                                item: layout.item,
                                isDragging: adjustment.isDragging,
                                onDrag: { edge, value in
                                    drag(layout.item, edge: edge, value: value)
                                },
                                onEnd: releaseAdjustment
                            )
                        }
                    }
                    .modifier(
                        ScheduleCardLift(
                            isPressed: isSelected(layout.item) && adjustment.isDragging)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected(layout.item), allowsAdjustment {
                            TimelineAdjustmentActions(
                                item: layout.item,
                                isSaving: adjustment.isSaving,
                                onCancel: onCancel, onDiscard: onDiscard, onDone: onDone,
                                onDelete: onDelete
                            )
                            .fixedSize()
                            // Leave the duration handle its own touch area below the card.
                            .offset(y: layout.rect.height + 4)
                        }
                    }
                    .zIndex(isSelected(layout.item) ? 1 : 0)
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
                including: allowsAdjustment && (!adjustment.isActive || bookingDrag != nil)
                    ? .all : .subviews
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in
                        guard allowsAdjustment, itemInteractionsEnabled, !adjustment.isActive,
                            let touchStart
                        else { return }
                        let y = touchStart.y - geometry.frame(in: .global).minY
                        // Use the displayed scale, including a compact break, for touch mapping.
                        bookingDrag = onBeginBooking(scale.time(at: y))
                    },
                including: allowsAdjustment && (!adjustment.isActive || bookingDrag != nil)
                    ? .all : .subviews
            )
        }
        .frame(height: scale.totalHeight)
        .padding(.vertical, Timeline.metrics.verticalPadding)
    }

    private func isSelected(_ item: TimelineItem) -> Bool {
        guard let id = adjustment.selectedID else { return false }
        return item.id == id
    }

    private func drag(
        _ item: TimelineItem, edge: TimelineAdjustment.Edge, value: DragGesture.Value
    ) {
        if !adjustment.isDragging { adjustment.begin(item, edge: edge, items: items) }
        onScaleChange(adjustment.update(translation: value.translation.height, items: items))
    }

    private func releaseAdjustment() {
        guard adjustment.isDragging else { return }
        lastDragEnd = .now
        adjustment.release()
    }

    private func nowY(for now: Date?) -> CGFloat? {
        guard let now else {
            return nil
        }

        let time = now.timeOfDay
        let scale = allowsAdjustment ? adjustment.scale(items, on: date) : scale
        guard scale.showsTime(time) else {
            return nil
        }

        return scale.yOffset(for: time)
    }
}

private struct TimelineCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // The lift owns press feedback. System button dimming would also fade the white fill.
        configuration.label
    }
}

private struct TimelineAdjustmentActions: View {
    let item: TimelineItem
    let isSaving: Bool
    let onCancel: () -> Void
    let onDiscard: () -> Void
    let onDone: @MainActor () async -> Void
    let onDelete: (@MainActor () async -> Void)?
    @State private var confirmsDiscard = false

    var body: some View {
        GlassEffectContainer {
            HStack {
                if let onDelete {
                    ConfirmingAsyncButton(
                        "Delete Unavailable Time", role: .destructive,
                        message: Text("Delete this unavailable time?"),
                        onConfirmation: onCancel
                    ) {
                        await onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.glass)
                }
                Button("Cancel", systemImage: "xmark") {
                    onCancel()
                    confirmsDiscard = true
                }
                .buttonStyle(.glass)
                .confirmationDialog(discardTitle, isPresented: $confirmsDiscard) {
                    Button("Discard Changes", role: .destructive, action: onDiscard)
                } message: {
                    Text(discardMessage)
                }
                AsyncButton("Done", systemImage: "checkmark", action: onDone)
                    .buttonStyle(.appGlassProminent)
            }
            .labelStyle(.iconOnly)
            .controlSize(.mini)
            .disabled(isSaving)
        }
    }

    private var discardTitle: String {
        switch item {
        case .appointment: "Discard unsaved appointment?"
        case .unavailableTime: "Discard unsaved unavailable time?"
        }
    }

    private var discardMessage: String {
        switch item {
        case .appointment: "Your appointment changes have not been saved."
        case .unavailableTime: "Your unavailable time changes have not been saved."
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
        previewNowMarker: Date.now.setTime(9, 30)
    )
    .background(AppColor.background)
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

private struct TimelineAdjustmentHandles: View {
    @Dependency(\.calendar) private var calendar
    let item: TimelineItem
    let isDragging: Bool
    let onDrag: (TimelineAdjustment.Edge, DragGesture.Value) -> Void
    let onEnd: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
            .strokeBorder(AppColor.accent, lineWidth: 2)
            .allowsHitTesting(false)
            .overlay(alignment: .bottom) { durationHandle() }
            .overlay(alignment: .topLeading) {
                if isDragging {
                    Text(
                        "\(item.start.formatted(date: .omitted, time: .shortened)) – \(item.end(using: calendar).formatted(date: .omitted, time: .shortened)) · \(item.durationMinutes) min"
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppColor.onAccent)
                    .padding(6)
                    .background(AppColor.accent, in: .capsule)
                    .fixedSize()
                    .offset(y: -32)
                    .allowsHitTesting(false)
                }
            }
    }

    private func durationHandle() -> some View {
        Capsule()
            .fill(AppColor.accent)
            .frame(width: 22, height: 10)
            .overlay {
                VStack(spacing: 2) {
                    Capsule().frame(width: 12, height: 1)
                    Capsule().frame(width: 12, height: 1)
                }
                .foregroundStyle(AppColor.onAccent.opacity(0.65))
            }
            .frame(width: 44, height: 28)
            .contentShape(.rect)
            // Half the touch area keeps the grip centered on the card's bottom edge.
            .offset(y: 14)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { onDrag(.duration, $0) }
                    .onEnded {
                        onDrag(.duration, $0)
                        onEnd()
                    }
            )
            .accessibilityIdentifier(durationHandleID)
    }

    private var durationHandleID: String {
        switch item {
        case .appointment: "appointment-duration-handle"
        case .unavailableTime: "unavailable-time-duration-handle"
        }
    }
}
