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
    var onAdjustAppointment: ((Appointment) async throws -> Void)? = nil
    var onDraggingChanged: (Bool) -> Void = { _ in }
    var onScaleChange: (CGFloat) -> Void = { _ in }

    var date: Date = .now
    @State var adjustment = TimelineAdjustment()
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
            onDraggingChanged(dragging)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: adjustment.isDragging)
        .sensoryFeedback(.selection, trigger: adjustment.preview?.start)
        .sensoryFeedback(.selection, trigger: adjustment.preview?.durationMinutes)
    }

    private func timelineContent(now: Date?) -> some View {
        let scale = onAdjustAppointment == nil ? scale : adjustment.scale(items, on: date)
        return GeometryReader { geometry in
            let engine = TimelineLayoutEngine(
                availableWidth: geometry.size.width,
                scale: scale
            )
            let layouts = engine.layout(
                items: adjustment.items(items, on: date),
                floatingID: adjustment.selectedID.map(TimelineItem.ID.appointment))

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
                        ScheduleItemCard(item: layout.item, isAdjusting: isSelected(layout.item))
                            .frame(width: layout.rect.width, height: layout.rect.height)
                            // Keep clipped text within the card's tap area.
                            // Regression tests: testLongNameDoesNotStealTapFromRightAppointment()
                            // and testMixedThreeColumnCardsKeepSeparateTapAreas().
                            .contentShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
                            .clipShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
                            .overlay {
                                if case .appointment = layout.item {
                                    RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
                                        .strokeBorder(.gray.opacity(0.15))
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(itemInteractionsEnabled)
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
                                if isSelected(layout.item), !adjustment.isDragging,
                                    case .appointment(let appointment) = layout.item
                                {
                                    adjustment.begin(appointment, edge: .move, items: items)
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
                                    saveAdjustment()
                                }
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .onEnded { _ in
                                guard onAdjustAppointment != nil, itemInteractionsEnabled,
                                    case .appointment(let appointment) = layout.item,
                                    appointment.status == .scheduled,
                                    !adjustment.isActive || isSelected(layout.item)
                                else { return }
                                adjustment.begin(appointment, edge: .move, items: items)
                            }
                    )
                    .overlay {
                        // Handles sit outside the body gesture so a resize cannot start a move.
                        if case .appointment(let appointment) = layout.item,
                            adjustment.selectedID == appointment.id,
                            onAdjustAppointment != nil, appointment.status == .scheduled
                        {
                            TimelineAdjustmentHandles(
                                appointment: appointment,
                                isDragging: adjustment.isDragging,
                                onDrag: { edge, value in
                                    drag(appointment, edge: edge, value: value)
                                },
                                onEnd: saveAdjustment
                            )
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
        }
        .frame(height: scale.totalHeight)
        .padding(.vertical, Timeline.metrics.verticalPadding)
    }

    private func isSelected(_ item: TimelineItem) -> Bool {
        guard let id = adjustment.selectedID else { return false }
        return item.id == .appointment(id)
    }

    private func drag(
        _ appointment: Appointment, edge: TimelineAdjustment.Edge, value: DragGesture.Value
    ) {
        if !adjustment.isDragging { adjustment.begin(appointment, edge: edge, items: items) }
        onScaleChange(adjustment.update(translation: value.translation.height, items: items))
    }

    private func saveAdjustment() {
        guard adjustment.isDragging else { return }
        lastDragEnd = .now
        guard let appointment = adjustment.release(),
            let onAdjustAppointment
        else { return }
        Task {
            do { try await onAdjustAppointment(appointment) } catch {
                adjustment.errorMessage = "The appointment could not be saved. Try again."
                adjustment.finish()
                return
            }
            adjustment.didSave()
        }
    }

    private func nowY(for now: Date?) -> CGFloat? {
        guard let now else {
            return nil
        }

        let time = now.timeOfDay
        let scale = onAdjustAppointment == nil ? scale : adjustment.scale(items, on: date)
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

private struct TimelineAdjustmentHandles: View {
    let appointment: Appointment
    let isDragging: Bool
    let onDrag: (TimelineAdjustment.Edge, DragGesture.Value) -> Void
    let onEnd: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
            .strokeBorder(.tint, lineWidth: 2)
            .allowsHitTesting(false)
            .overlay(alignment: .topTrailing) { handle(.start) }
            .overlay(alignment: .bottomTrailing) { handle(.end) }
            .overlay(alignment: .topLeading) {
                if isDragging {
                    Text(
                        "\(appointment.start.formatted(date: .omitted, time: .shortened)) – \(appointment.end.formatted(date: .omitted, time: .shortened)) · \(appointment.durationMinutes) min"
                    )
                    .font(.caption2.monospacedDigit())
                    .padding(6)
                    .background(.regularMaterial, in: .capsule)
                    .fixedSize()
                    .offset(y: -32)
                    .allowsHitTesting(false)
                }
            }
    }

    private func handle(_ edge: TimelineAdjustment.Edge) -> some View {
        Capsule()
            .fill(.tint)
            .frame(width: 22, height: 5)
            .frame(width: 44, height: 28)
            .contentShape(.rect)
            .offset(y: edge == .start ? -10 : 10)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { onDrag(edge, $0) }
                    .onEnded {
                        onDrag(edge, $0)
                        onEnd()
                    }
            )
            .accessibilityIdentifier(
                edge == .start ? "appointment-start-handle" : "appointment-end-handle")
    }
}
