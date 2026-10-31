import ClinicalModels
import SwiftUI

struct ScheduleTimelinePage: View {
    let date: Date
    let items: [TimelineItem]
    let calendar: Calendar
    let itemInteractionsEnabled: Bool
    @Binding var scrollPosition: ScrollPosition
    let onSelectItem: (TimelineItem) -> Void
    let onSelectDraft: () -> Void
    let allowsAdjustment: Bool
    let editorSession: ScheduleEditorSession?
    let isWorking: Bool
    let onBeginBooking: (TimeOfDay) -> ScheduleEditorSession?
    let onBookingRelease: (TimelineAdjustment) -> Void
    let onCancel: () -> Void
    let onDiscard: () -> Void
    let onDone: @MainActor () async -> Void
    let onDelete: (@MainActor () async -> Void)?
    @State private var isDragging = false
    @State private var scrollY: CGFloat = 0
    @State private var needsAdjustmentClearance = false
    @State private var pendingScrollY: CGFloat?
    @State private var timelineTop: CGFloat = 0
    @State private var touchStart: CGPoint?
    @State private var lastDragEnd: ContinuousClock.Instant?
    // Keep the first touch attached while Schedule installs the new booking session.
    @State private var bookingDrag: ScheduleEditorSession?

    var body: some View {
        let timelinePadding = Timeline.metrics.verticalPadding
        ScrollView {
            VStack(spacing: 0) {
                Timeline(
                    items: items,
                    scale: TimelineScale(items: items),
                    showsNowMarker: calendar.isDateInToday(date),
                    itemInteractionsEnabled: itemInteractionsEnabled,
                    onSelectItem: { if allowsSelection { onSelectItem($0) } },
                    onSelectDraft: { if allowsSelection { onSelectDraft() } },
                    allowsAdjustment: allowsAdjustment,
                    onDraggingChanged: {
                        isDragging = $0
                        if $0 { needsAdjustmentClearance = true }
                        if !$0 {
                            bookingDrag = nil
                            touchStart = nil
                        }
                    },
                    onScaleChange: correctScrollPosition,
                    onCancel: onCancel,
                    onDiscard: onDiscard,
                    onDone: onDone,
                    onDelete: onDelete,
                    date: date,
                    editorSession: editorSession,
                    isWorking: isWorking
                )
                .onGeometryChange(for: CGFloat.self) {
                    $0.frame(in: .global).minY + timelinePadding
                } action: {
                    timelineTop = $0
                }

                if needsAdjustmentClearance {
                    // Direct adjustment needs scroll range to anchor an expanding break.
                    Color.clear
                        .containerRelativeFrame(
                            .vertical,
                            count: 2,
                            span: 1,
                            spacing: 0
                        )
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: { _ in
                guard let pendingScrollY else { return }
                scrollPosition.scrollTo(y: pendingScrollY)
                self.pendingScrollY = nil
            }
        }
        .onChange(of: editorSession != nil, initial: true) {
            needsAdjustmentClearance = editorSession != nil
        }
        .scrollDisabled(isDragging)
        // In iOS 26, gestures inside the content can block the scroll view's native pan.
        // Keep booking touch tracking on the scroll view so both can receive the same swipe.
        .simultaneousGesture(
            // Measure from touch-down so the hold does not lose the first movement.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    touchStart = value.startLocation
                    // A swipe must cancel selection even when the day is too short to scroll.
                    if abs(value.translation.height) > 5 || abs(value.translation.width) > 5 {
                        lastDragEnd = .now
                    }
                    if let bookingDrag {
                        correctScrollPosition(
                            bookingDrag.updateAdjustment(
                                translation: value.translation.height, items: items))
                    }
                }
                .onEnded { value in
                    touchStart = nil
                    guard let bookingDrag else { return }
                    self.bookingDrag = nil
                    // Done or Cancel can end the drag before the finger lifts.
                    guard bookingDrag.adjustment.isDragging else { return }
                    lastDragEnd = .now
                    correctScrollPosition(
                        bookingDrag.updateAdjustment(
                            translation: value.translation.height, items: items))
                    bookingDrag.adjustment.release()
                    onBookingRelease(bookingDrag.adjustment)
                },
            including: allowsAdjustment && (editorSession == nil || bookingDrag != nil)
                ? .all : .subviews
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    guard allowsAdjustment, itemInteractionsEnabled,
                        editorSession == nil, let touchStart
                    else { return }
                    let y = touchStart.y - timelineTop
                    // Use the displayed scale, including a compact break, for touch mapping.
                    bookingDrag = onBeginBooking(TimelineScale(items: items).time(at: y))
                },
            including: allowsAdjustment && (editorSession == nil || bookingDrag != nil)
                ? .all : .subviews
        )
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y + $0.contentInsets.top
        } action: { _, y in
            scrollY = y
        }
        .modifier(TimelineScrollModifier(scrollPosition: $scrollPosition))
    }

    private var allowsSelection: Bool {
        // A hold can finish in the same event as the button release.
        lastDragEnd.map { $0.duration(to: .now) > .milliseconds(150) } ?? true
    }

    private func correctScrollPosition(_ delta: CGFloat) {
        guard delta != 0 else { return }
        pendingScrollY = max(scrollY + delta, 0)
    }
}

private struct TimelineScrollModifier: ViewModifier {
    @Binding var scrollPosition: ScrollPosition
    @State private var isScrolled = false

    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.basedOnSize)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 1
            } action: { _, isScrolled in
                self.isScrolled = isScrolled
            }
            .overlay(alignment: .top) {
                if isScrolled {
                    TimelineTopScrollFade()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isScrolled)
    }
}

private struct TimelineTopScrollFade: View {
    @Environment(\.appPalette) private var palette
    var body: some View {
        LinearGradient(
            colors: [
                palette[.canvas],
                palette[.canvas].opacity(0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 20)
        .allowsHitTesting(false)
    }
}
