import ClinicalModels
import SwiftUI

struct ScheduleTimelinePage: View {
    @Environment(\.scheduleCardTuning) private var cardTuning

    let date: Date
    let today: Date
    let items: [TimelineItem]
    let itemInteractionsEnabled: Bool
    var selectedAppointmentID: Appointment.ID? = nil
    @Binding var scrollPosition: ScrollPosition
    let allowsAdjustment: Bool
    let editorSession: ScheduleEditorSession?
    let onSelectItem: (TimelineItem) -> Void
    let onBeginHold: (TimelineItem?, TimeOfDay) -> ScheduleEditorSession?
    @State private var isDragging = false
    @State private var scrollY: CGFloat = 0
    @State private var needsAdjustmentClearance = false
    @State private var pendingScrollY: CGFloat?
    @State private var timelineFrame = CGRect.zero
    @State private var touchStart: CGPoint?
    @State private var holdRecognized = false
    @GestureState private var touchActive = false
    @State private var swipeCooldown = TimelineDragCooldown()
    // Keep the first touch attached while Schedule installs the editor session.
    @State private var holdSession: ScheduleEditorSession?

    var body: some View {
        let timelinePadding = Timeline.metrics.verticalPadding
        let showsNowMarker = date.isSameDayAs(today)
        ScrollView {
            VStack(spacing: 0) {
                Timeline(
                    items: items,
                    scale: TimelineScale(items: items),
                    showsNowMarker: showsNowMarker,
                    previewNowMarker: showsNowMarker ? debugNowMarker : nil,
                    itemInteractionsEnabled: itemInteractionsEnabled,
                    selectedAppointmentID: selectedAppointmentID,
                    canSelect: { swipeCooldown.allowsSelection },
                    onSelectItem: onSelectItem,
                    allowsAdjustment: allowsAdjustment,
                    onDraggingChanged: {
                        isDragging = $0
                        if $0 { needsAdjustmentClearance = true }
                        if !$0 {
                            holdSession = nil
                            touchStart = nil
                            holdRecognized = false
                        }
                    },
                    onScaleChange: correctScrollPosition,
                    date: date,
                    editorSession: editorSession
                )
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global).insetBy(dx: 0, dy: timelinePadding)
                } action: {
                    timelineFrame = $0
                }

                if needsAdjustmentClearance || selectedAppointmentID != nil {
                    // Direct adjustment and open appointment details need bottom scroll range
                    // so evening appointments can scroll clear of the tray.
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
        .onChange(of: touchActive) { _, active in
            if !active {
                // Draft layout can reset gesture state before the finger lifts.
                // Only the drag's onEnded may release the draft and open its sheet.
                touchStart = nil
                holdRecognized = false
            }
        }
        // In iOS 26, gestures inside the content can block the scroll view's native pan.
        // Keep touch tracking on the scroll view so both can receive the same swipe.
        .simultaneousGesture(
            // Measure from touch-down so the hold does not lose the first movement.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    touchStart = value.startLocation
                    // A swipe must cancel selection even when the day is too short to scroll.
                    if abs(value.translation.height) > 5 || abs(value.translation.width) > 5 {
                        swipeCooldown.record()
                    }
                    beginHoldIfReady()
                    if let holdSession {
                        correctScrollPosition(
                            holdSession.updateAdjustment(
                                translation: value.translation.height, items: items))
                    }
                }
                .onEnded { value in
                    if holdRecognized || holdSession != nil { swipeCooldown.record() }
                    touchStart = nil
                    holdRecognized = false
                    guard let holdSession else { return }
                    self.holdSession = nil
                    // Done or Cancel can end the drag before the finger lifts.
                    guard holdSession.adjustment.isDragging else { return }
                    correctScrollPosition(
                        holdSession.updateAdjustment(
                            translation: value.translation.height, items: items))
                    holdSession.adjustment.release()
                    if holdSession.allowsTypeSelection {
                        holdSession.releaseBooking(holdSession.adjustment)
                    }
                }
                // Clear a completed hold when this touch ends or is cancelled.
                .updating($touchActive) { _, active, _ in active = true },
            including: allowsAdjustment && (editorSession == nil || holdSession != nil)
                ? .all : .subviews
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    // A phone can complete the hold before the drag supplies its position.
                    holdRecognized = true
                    beginHoldIfReady()
                },
            including: allowsAdjustment && (editorSession == nil || holdSession != nil)
                ? .all : .subviews
        )
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y + $0.contentInsets.top
        } action: { _, y in
            scrollY = y
        }
        .modifier(TimelineScrollModifier(scrollPosition: $scrollPosition))
    }

    private func beginHoldIfReady() {
        guard holdRecognized, let touchStart, allowsAdjustment, itemInteractionsEnabled,
            editorSession == nil, holdSession == nil
        else { return }
        swipeCooldown.record()
        let point = CGPoint(
            x: touchStart.x - timelineFrame.minX, y: touchStart.y - timelineFrame.minY)
        // Use the displayed scale, including a compact break, for touch mapping.
        let scale = TimelineScale(items: items)
        let layout = TimelineLayoutEngine(
            availableWidth: timelineFrame.width,
            scale: scale,
            overlap: cardTuning.overlap
        )
        // Check the front card first when cards overlap.
        let item = layout.layout(items: items).last {
            TimelineItemView.cardShape.path(in: $0.rect).contains(point)
        }?.item
        holdSession = onBeginHold(item, scale.time(at: point.y))
    }

    private func correctScrollPosition(_ delta: CGFloat) {
        guard delta != 0 else { return }
        pendingScrollY = max(scrollY + delta, 0)
    }

    private var debugNowMarker: Date? {
        #if DEBUG
            Self.debugNowTime?.on(date: date)
        #else
            nil
        #endif
    }

    #if DEBUG
        private static let debugNowTime: TimeOfDay? = {
            let arguments = CommandLine.arguments
            guard let index = arguments.firstIndex(of: "--now"),
                arguments.indices.contains(index + 1)
            else { return nil }
            let parts = arguments[index + 1].split(separator: ":")
            guard parts.count == 2,
                let hour = Int(parts[0]), (0..<24).contains(hour),
                let minute = Int(parts[1]), (0..<60).contains(minute)
            else { return nil }
            return TimeOfDay(hour, minute)
        }()
    #endif
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
            .animation(AppMotion.animation(.easeInOut(duration: 0.18)), value: isScrolled)
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
