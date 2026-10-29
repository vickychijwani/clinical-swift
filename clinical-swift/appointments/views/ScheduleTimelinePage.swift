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

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Timeline(
                    items: items,
                    scale: TimelineScale(items: items),
                    showsNowMarker: calendar.isDateInToday(date),
                    itemInteractionsEnabled: itemInteractionsEnabled,
                    onSelectItem: onSelectItem,
                    onSelectDraft: onSelectDraft,
                    allowsAdjustment: allowsAdjustment,
                    onDraggingChanged: {
                        isDragging = $0
                        if $0 { needsAdjustmentClearance = true }
                    },
                    onScaleChange: { delta in
                        guard delta != 0 else { return }
                        pendingScrollY = max(scrollY + delta, 0)
                    },
                    onBeginBooking: onBeginBooking,
                    onBookingRelease: onBookingRelease,
                    onCancel: onCancel,
                    onDiscard: onDiscard,
                    onDone: onDone,
                    onDelete: onDelete,
                    date: date,
                    editorSession: editorSession,
                    isWorking: isWorking
                )

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
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y + $0.contentInsets.top
        } action: { _, y in
            scrollY = y
        }
        .modifier(TimelineScrollModifier(scrollPosition: $scrollPosition))
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
