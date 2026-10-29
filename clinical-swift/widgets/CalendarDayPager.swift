import ClinicalModels
import SwiftUI

struct CalendarDayPager<Content: View>: View {
    @Binding var selectedDate: Date

    let calendar: Calendar
    let dayRadius: Int
    let isPagingEnabled: Bool
    let content: (Date) -> Content

    @State private var visibleDate: Date
    @State private var visiblePage: Int? = 0
    @State private var pendingPage: Int?
    @State private var isScrollActive = false

    init(
        selectedDate: Binding<Date>,
        calendar: Calendar = .autoupdatingCurrent,
        dayRadius: Int,
        isPagingEnabled: Bool = true,
        @ViewBuilder content: @escaping (Date) -> Content
    ) {
        self._selectedDate = selectedDate
        self.calendar = calendar
        self.dayRadius = max(dayRadius, 1)
        self.isPagingEnabled = isPagingEnabled
        self.content = content
        self._visibleDate = State(
            initialValue: selectedDate.wrappedValue.startOfDay(using: calendar)
        )
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(-dayRadius...dayRadius, id: \.self) { page in
                    content(
                        visibleDate.date(
                            byAddingDays: page,
                            using: calendar
                        )
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollDisabled(!isPagingEnabled)
        .scrollPosition(id: $visiblePage)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    // Timeline touch tracking can prevent the scroll view's pan from starting.
                    guard isPagingEnabled, !isScrollActive, visiblePage == 0,
                        abs(value.translation.width) > 50,
                        abs(value.translation.width) > abs(value.translation.height) * 2
                    else { return }
                    isScrollActive = true
                    withAnimation(.easeOut(duration: 0.25)) {
                        visiblePage = value.translation.width < 0 ? 1 : -1
                    }
                }
        )
        .onAppear(perform: normalizeSelection)
        .onChange(of: visiblePage) {
            guard let visiblePage else {
                return
            }

            pendingPage = visiblePage == 0 ? nil : visiblePage

            if !isScrollActive {
                commitPendingPage()
            }
        }
        .onScrollPhaseChange { _, newPhase in
            isScrollActive = newPhase.isScrolling

            if newPhase == .idle {
                commitPendingPage()
            }
        }
        .onChange(of: selectedDate) {
            let normalizedDate = selectedDate.startOfDay(using: calendar)

            if selectedDate != normalizedDate {
                selectedDate = normalizedDate
            }

            guard !normalizedDate.isSameDayAs(visibleDate) else {
                return
            }

            visibleDate = normalizedDate
            visiblePage = 0
            pendingPage = nil
        }
    }

    private func normalizeSelection() {
        selectedDate = selectedDate.startOfDay(using: calendar)
        visibleDate = selectedDate
        visiblePage = 0
        pendingPage = nil
    }

    private func moveVisibleDay(by dayOffset: Int) {
        selectedDate = selectedDate.date(
            byAddingDays: dayOffset,
            using: calendar
        )
        visibleDate = visibleDate.date(
            byAddingDays: dayOffset,
            using: calendar
        )
    }

    private func commitPendingPage() {
        guard let pendingPage else {
            return
        }

        moveVisibleDay(by: pendingPage)
        self.pendingPage = nil
        visiblePage = 0
    }
}
