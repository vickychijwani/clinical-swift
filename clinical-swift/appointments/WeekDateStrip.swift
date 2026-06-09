import SwiftUI

struct WeekDateStrip: View {
    @Binding var selectedDate: Date

    let today: Date
    let calendar: Calendar

    @State private var visibleWeekStart: Date
    @State private var visiblePage: WeekPageOffset? = .current
    @State private var pendingPage: WeekPageOffset?
    @State private var isScrollActive = false

    init(
        selectedDate: Binding<Date>,
        today: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self._selectedDate = selectedDate
        self.today = today.startOfDay(using: calendar)
        self.calendar = calendar
        self._visibleWeekStart = State(
            initialValue: selectedDate.wrappedValue.startOfWeek(using: calendar)
        )
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(WeekPageOffset.allCases) { page in
                    WeekDatePage(
                        weekStart: visibleWeekStart.date(
                            byAddingWeeks: page.weekOffset,
                            using: calendar
                        ),
                        selectedDate: selectedDate,
                        today: today,
                        calendar: calendar,
                        selectDate: selectDate
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
        .frame(height: 88)
        .onAppear(perform: normalizeSelection)
        .onChange(of: visiblePage) { _, newPage in
            guard let newPage else {
                return
            }

            // Recenter only after scrolling stops; doing it mid-deceleration lets one fast swipe consume another week.
            pendingPage = newPage == .current ? nil : newPage

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
        .onChange(of: selectedDate) { _, newDate in
            let normalizedDate = newDate.startOfDay(using: calendar)

            if selectedDate != normalizedDate {
                selectedDate = normalizedDate
            }

            if !isDateVisible(normalizedDate) {
                visibleWeekStart = normalizedDate.startOfWeek(using: calendar)
            }
        }
    }

    private func normalizeSelection() {
        selectedDate = selectedDate.startOfDay(using: calendar)
        visibleWeekStart = selectedDate.startOfWeek(using: calendar)
        visiblePage = .current
        pendingPage = nil
    }

    private func selectDate(_ date: Date) {
        selectedDate = date.startOfDay(using: calendar)
    }

    private func moveVisibleWeek(by weekOffset: Int) {
        selectedDate = selectedDate.date(
            byAddingWeeks: weekOffset,
            using: calendar
        )
        visibleWeekStart = visibleWeekStart.date(
            byAddingWeeks: weekOffset,
            using: calendar
        )
    }

    private func commitPendingPage() {
        guard let pendingPage else {
            return
        }

        moveVisibleWeek(by: pendingPage.weekOffset)
        self.pendingPage = nil
        visiblePage = .current
    }

    private func isDateVisible(_ date: Date) -> Bool {
        visibleWeekStart.weekDates(using: calendar).contains { visibleDate in
            calendar.isDate(visibleDate, inSameDayAs: date)
        }
    }
}

private enum WeekPageOffset: Int, CaseIterable, Identifiable {
    case previous = -1
    case current = 0
    case next = 1

    var id: Self {
        self
    }

    var weekOffset: Int {
        rawValue
    }
}

private struct WeekDatePage: View {
    let weekStart: Date
    let selectedDate: Date
    let today: Date
    let calendar: Calendar
    let selectDate: (Date) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekStart.weekDates(using: calendar), id: \.self) { date in
                DateStripCell(
                    date: date,
                    isSelected: calendar.isDate(
                        date,
                        inSameDayAs: selectedDate
                    ),
                    isToday: calendar.isDate(date, inSameDayAs: today),
                    selectDate: selectDate
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }
}

private struct DateStripCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let selectDate: (Date) -> Void

    var body: some View {
        Button {
            selectDate(date)
        } label: {
            VStack(spacing: 6) {
                Text(weekdayText)
                    .font(.caption)
                    .bold()

                Text(dayText)
                    .font(.title3)
                    .bold()
            }
            .foregroundStyle(foregroundStyle)
            .frame(minWidth: 44, minHeight: 64)
            .background {
                if isSelected {
                    ZStack {
                        Color("AppBackground")
                        Color.primary.opacity(0.06)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foregroundStyle: Color {
        if isToday {
            .accentColor
        } else if isSelected {
            .primary
        } else {
            .secondary
        }
    }

    private var weekdayText: String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    private var dayText: String {
        date.formatted(.dateTime.day())
    }

    private var accessibilityLabel: String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    private var accessibilityValue: String {
        [isToday ? "Today" : nil, isSelected ? "Selected" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    @Previewable @State var selectedDate = Date.now.startOfDay()

    WeekDateStrip(selectedDate: $selectedDate, today: .now)
        .background(Color("AppBackground"))
}
