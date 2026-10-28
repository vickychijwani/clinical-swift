import ClinicalModels
import Dependencies
import SwiftUI

struct TimelineItemView: View {
    let item: TimelineItem
    let size: CGSize
    let isSelected: Bool
    let isDeemphasized: Bool
    let interactionsEnabled: Bool
    let showsAdjustmentControls: Bool
    let isDragging: Bool
    let isWorking: Bool
    let onSelect: () -> Void
    let onMoveChanged: (DragGesture.Value) -> Void
    let onMoveEnded: (DragGesture.Value) -> Void
    let onResizeChanged: (DragGesture.Value) -> Void
    let onResizeEnded: () -> Void
    let onCancel: () -> Void
    let onDiscard: () -> Void
    let onDone: @MainActor () async -> Void
    let onDelete: (@MainActor () async -> Void)?

    var body: some View {
        let tooltipBelow = item.start.timeOfDay.minutes(since: Bitehaus.opening) <= 30

        Button(action: onSelect) {
            ScheduleItemCard(
                item: item,
                isAdjusting: isSelected,
                isDeemphasized: isDeemphasized
            )
            .frame(width: size.width, height: size.height)
            // Keep clipped text within the card's tap area.
            // Regression tests: testLongNameDoesNotStealTapFromRightAppointment()
            // and testMixedThreeColumnCardsKeepSeparateTapAreas().
            .contentShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
            .clipShape(.rect(cornerRadius: ScheduleCardStyle.cornerRadius))
            .overlay {
                if case .appointment = item {
                    RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
                        .strokeBorder(.gray.opacity(0.15))
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(TimelineCardButtonStyle())
        .allowsHitTesting(interactionsEnabled)
        // UI tests use the item type and ID to select each card.
        .accessibilityIdentifier(item.id.sortKey)
        .accessibilityValue("\(item.durationMinutes) min")
        .simultaneousGesture(
            // Measure from touch-down so the hold does not lose the first movement.
            // A swipe must cancel selection even when the day is too short to scroll.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged(onMoveChanged)
                .onEnded(onMoveEnded)
        )
        .overlay {
            // Handles sit outside the body gesture so a resize cannot start a move.
            if showsAdjustmentControls, item.allowsAdjustment {
                TimelineAdjustmentHandles(
                    item: item,
                    onDrag: onResizeChanged,
                    onEnd: onResizeEnded
                )
            }
        }
        .modifier(ScheduleCardLift(isPressed: isSelected && isDragging))
        .overlay(alignment: .topLeading) {
            if showsAdjustmentControls, isDragging, !tooltipBelow {
                TimelineAdjustmentTooltip(item: item)
                    .visualEffect { content, geometry in
                        content.offset(y: -geometry.size.height - 4)
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsAdjustmentControls {
                HStack {
                    if isDragging, tooltipBelow {
                        // Keep the tooltip clear of the duration grip and card actions.
                        TimelineAdjustmentTooltip(item: item)
                    }
                    Spacer(minLength: 0)
                    TimelineAdjustmentActions(
                        item: item,
                        isSaving: isWorking,
                        onCancel: onCancel, onDiscard: onDiscard, onDone: onDone,
                        onDelete: onDelete
                    )
                    .fixedSize()
                }
                .frame(width: size.width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                // Leave the duration handle its own touch area below the card.
                .offset(y: size.height + 4)
            }
        }
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
                    .buttonStyle(.glassProminent)
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

private struct TimelineAdjustmentHandles: View {
    let item: TimelineItem
    let onDrag: (DragGesture.Value) -> Void
    let onEnd: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
            .strokeBorder(.tint, lineWidth: 2)
            .allowsHitTesting(false)
            .overlay(alignment: .bottom) { durationHandle() }
    }

    private func durationHandle() -> some View {
        Capsule()
            .fill(.tint)
            .frame(width: 22, height: 10)
            .overlay {
                VStack(spacing: 2) {
                    Capsule().frame(width: 12, height: 1)
                    Capsule().frame(width: 12, height: 1)
                }
                .foregroundStyle(.white.opacity(0.65))
            }
            .frame(width: 44, height: 28)
            .contentShape(.rect)
            // Half the touch area keeps the grip centered on the card's bottom edge.
            .offset(y: 14)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged(onDrag)
                    .onEnded {
                        onDrag($0)
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

private struct TimelineAdjustmentTooltip: View {
    @Dependency(\.calendar) private var calendar
    let item: TimelineItem

    var body: some View {
        Text(
            "\(item.start.formatted(date: .omitted, time: .shortened)) – \(item.end(using: calendar).formatted(date: .omitted, time: .shortened)) · \(item.durationMinutes) min"
        )
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.white)
        .padding(6)
        .background(Color.accentColor, in: .capsule)
        .fixedSize()
        .allowsHitTesting(false)
    }
}
