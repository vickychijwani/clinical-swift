import SwiftUI

struct CalendarDayPager<Content: View>: View {
    @Binding var selectedDate: Date

    let calendar: Calendar
    let content: (Date) -> Content

    @State private var visibleDate: Date
    @State private var visiblePage: CalendarDayPageOffset? = .current
    @State private var pendingPage: CalendarDayPageOffset?
    @State private var isScrollActive = false

    init(
        selectedDate: Binding<Date>,
        calendar: Calendar = .autoupdatingCurrent,
        @ViewBuilder content: @escaping (Date) -> Content
    ) {
        self._selectedDate = selectedDate
        self.calendar = calendar
        self.content = content
        self._visibleDate = State(
            initialValue: selectedDate.wrappedValue.startOfDay(using: calendar)
        )
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(CalendarDayPageOffset.allCases) { page in
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

private enum CalendarDayPageOffset: Int, CaseIterable, Identifiable {
    case previous = -1
    case current = 0
    case next = 1

    var id: Self {
        self
    }

    var dayOffset: Int {
        rawValue
    }
}
