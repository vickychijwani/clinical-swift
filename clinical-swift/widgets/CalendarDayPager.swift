import SwiftUI

struct CalendarDayPager<Content: View>: View {
    @Binding var selectedDate: Date

    let calendar: Calendar
    let dayRadius: Int
    let content: (Date) -> Content

    @State private var visibleDate: Date
    @State private var visiblePage: CalendarDayPageOffset? = .current
    @State private var pendingPage: CalendarDayPageOffset?
    @State private var isScrollActive = false

    init(
        selectedDate: Binding<Date>,
        calendar: Calendar = .autoupdatingCurrent,
        dayRadius: Int,
        @ViewBuilder content: @escaping (Date) -> Content
    ) {
        self._selectedDate = selectedDate
        self.calendar = calendar
        self.dayRadius = max(dayRadius, 1)
        self.content = content
        self._visibleDate = State(
            initialValue: selectedDate.wrappedValue.startOfDay(using: calendar)
        )
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(pageOffsets) { page in
                    content(
                        visibleDate.date(
                            byAddingDays: page.dayOffset,
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
        .scrollPosition(id: $visiblePage)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: normalizeSelection)
        .onChange(of: visiblePage) {
            guard let visiblePage else {
                return
            }

            pendingPage = visiblePage == .current ? nil : visiblePage

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
            visiblePage = .current
            pendingPage = nil
        }
    }

    private var pageOffsets: [CalendarDayPageOffset] {
        (-dayRadius...dayRadius).map(CalendarDayPageOffset.init)
    }

    private func normalizeSelection() {
        selectedDate = selectedDate.startOfDay(using: calendar)
        visibleDate = selectedDate
        visiblePage = .current
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

        moveVisibleDay(by: pendingPage.dayOffset)
        self.pendingPage = nil
        visiblePage = .current
    }
}

private struct CalendarDayPageOffset: Hashable, Identifiable {
    static let current = CalendarDayPageOffset(dayOffset: 0)

    let dayOffset: Int

    var id: Int {
        dayOffset
    }
}
