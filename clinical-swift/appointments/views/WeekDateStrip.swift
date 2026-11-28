import ClinicalModels
import SwiftUI

private enum WeekStripMetrics {
    static let compactStripHeight: CGFloat = 64
    static let expandedStripHeight: CGFloat = 72
    static let stripHorizontalPadding: CGFloat = 8
    static let compactCellMinHeight: CGFloat = 56
    static let expandedCellMinHeight: CGFloat = 64
    static let cellCornerRadius: CGFloat = 16
}

struct WeekDateStrip: View {
    @Binding var selectedDate: Date

    let today: Date
    let calendar: Calendar
    let showsCapacityIndicators: Bool
    let dayCapacity: (Date) -> [DayCapacitySlot]

    @State private var visibleWeekStart: Date
    @State private var visiblePage: WeekPageOffset? = .current
    @State private var pendingPage: WeekPageOffset?
    @State private var isScrollActive = false

    init(
        selectedDate: Binding<Date>,
        today: Date,
        calendar: Calendar = ClinicDate.calendar,
        showsCapacityIndicators: Bool = true,
        dayCapacity: @escaping (Date) -> [DayCapacitySlot] = { _ in [] }
    ) {
        self._selectedDate = selectedDate
        self.today = today.startOfDay(using: calendar)
        self.calendar = calendar
        self.showsCapacityIndicators = showsCapacityIndicators
        self.dayCapacity = dayCapacity
        self._visibleWeekStart = State(
            initialValue: selectedDate.wrappedValue.startOfWeek(using: calendar)
        )
    }

    var body: some View {
        let stripHeight =
            showsCapacityIndicators
            ? WeekStripMetrics.expandedStripHeight : WeekStripMetrics.compactStripHeight

        ScrollView(.horizontal) {
            // Keep all three pages mounted so adjacent weeks stay current before a swipe starts.
            HStack(spacing: 0) {
                ForEach(WeekPageOffset.allCases) { page in
                    WeekDatePage(
                        weekStart: visibleWeekStart.date(
                            byAddingWeeks: page.weekOffset,
                            using: calendar
                        ),
                        selectedDate: selectedDate,
                        today: today,
                        calendar: calendar,
                        showsCapacityIndicators: showsCapacityIndicators,
                        dayCapacity: dayCapacity,
                        selectDate: selectDate
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        // Start centered on .current because an eager HStack otherwise opens at .previous.
        .defaultScrollAnchor(.center)
        .scrollPosition(id: $visiblePage)
        .scrollIndicators(.hidden)
        // Let the glass shadow extend below the strip without changing its layout height.
        .scrollClipDisabled()
        .frame(height: stripHeight)
        .onAppear(perform: normalizeSelection)
        .onChange(of: visiblePage) {
            guard let visiblePage else {
                return
            }

            // Recenter only after scrolling stops; doing it mid-deceleration lets one fast swipe consume another week.
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

            if !isDateVisible(normalizedDate) {
                // Snap week changes without animation so cells do not cross-fade.
                withoutAnimation {
                    visibleWeekStart = normalizedDate.startOfWeek(using: calendar)
                    visiblePage = .current
                    pendingPage = nil
                }
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
        visibleWeekStart = visibleWeekStart.date(
            byAddingWeeks: weekOffset,
            using: calendar
        )
        selectedDate = selectedDate.date(
            byAddingWeeks: weekOffset,
            using: calendar
        )
    }

    private func commitPendingPage() {
        guard let pendingPage else {
            return
        }

        // Recenter without animation so week swaps do not cross-fade or jump the selection pill.
        withoutAnimation {
            moveVisibleWeek(by: pendingPage.weekOffset)
            self.pendingPage = nil
            visiblePage = .current
        }
    }

    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }

    private func isDateVisible(_ date: Date) -> Bool {
        visibleWeekStart.weekDates(using: calendar).contains { visibleDate in
            visibleDate.isSameDayAs(date)
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
    @Environment(\.appPalette) private var palette
    @Environment(\.self) private var environment
    let weekStart: Date
    let selectedDate: Date
    let today: Date
    let calendar: Calendar
    let showsCapacityIndicators: Bool
    let dayCapacity: (Date) -> [DayCapacitySlot]
    let selectDate: (Date) -> Void

    @Namespace private var selectionGlass

    private var cellMinHeight: CGFloat {
        showsCapacityIndicators
            ? WeekStripMetrics.expandedCellMinHeight : WeekStripMetrics.compactCellMinHeight
    }

    var body: some View {
        let weekDates = weekStart.weekDates(using: calendar)
        let selectedSlot = weekDates.firstIndex { $0.isSameDayAs(selectedDate) }

        HStack(spacing: 8) {
            // Key cells by weekday slot so week shifts update text in place without cross-fading.
            ForEach(weekDates.enumerated(), id: \.offset) { slot, date in
                DateStripCell(
                    date: date,
                    slot: slot,
                    isSelected: date.isSameDayAs(selectedDate),
                    isToday: date.isSameDayAs(today),
                    isPast: date < today,
                    showsCapacityIndicators: showsCapacityIndicators,
                    cellMinHeight: cellMinHeight,
                    capacitySlots: showsCapacityIndicators ? dayCapacity(date) : [],
                    selectionGlass: selectionGlass,
                    selectDate: selectDate
                )
                .frame(maxWidth: .infinity)
            }
        }
        .background {
            if let selectedSlot {
                let tint: Color? =
                    if selectedDate.isSameDayAs(today), palette.todaySelection.highlightOpacity > 0
                    {
                        palette.opaqueAccent(in: environment)
                            .opacity(palette.todaySelection.highlightOpacity)
                    } else {
                        nil
                    }
                // Keep one glass view alive so date changes move it instead of fading separate effects.
                Color.clear
                    .frame(width: 44, height: cellMinHeight)
                    .glassEffect(
                        .regular.tint(tint).interactive(),
                        in: .rect(
                            cornerRadius: WeekStripMetrics.cellCornerRadius, style: .continuous)
                    )
                    .matchedGeometryEffect(
                        id: selectedSlot, in: selectionGlass, properties: .position, isSource: false
                    )
                    .animation(AppMotion.animation(.bouncy(duration: 0.35)), value: selectedSlot)
            }
        }
        .padding(.horizontal, WeekStripMetrics.stripHorizontalPadding)
    }
}

private struct DateStripCell: View {
    @Environment(\.appPalette) private var palette
    @Environment(\.self) private var environment
    let date: Date
    let slot: Int
    let isSelected: Bool
    let isToday: Bool
    let isPast: Bool
    let showsCapacityIndicators: Bool
    let cellMinHeight: CGFloat
    let capacitySlots: [DayCapacitySlot]
    let selectionGlass: Namespace.ID
    let selectDate: (Date) -> Void

    var body: some View {
        Button {
            selectDate(date)
        } label: {
            VStack(spacing: 0) {
                Text(weekdayText)
                    .font(.caption)
                    .bold()

                Text(dayText)
                    .font(.title3)
                    .bold()

                if showsCapacityIndicators {
                    DayCapacityIndicatorView(
                        slots: capacitySlots,
                        isToday: isToday,
                        isSelected: isSelected,
                        isPast: isPast
                    )
                    .padding(.top, 4)
                }
            }
            .foregroundStyle(foregroundStyle)
            .animation(AppMotion.animation(.bouncy(duration: 0.35)), value: isSelected)
            .frame(minWidth: 44, minHeight: cellMinHeight)
            .contentShape(
                .rect(cornerRadius: WeekStripMetrics.cellCornerRadius, style: .continuous)
            )
            .matchedGeometryEffect(id: slot, in: selectionGlass, properties: .position)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foregroundStyle: Color {
        if isToday {
            let accent = palette.opaqueAccent(in: environment)
            return isSelected ? palette.todaySelection.textColor(accent: accent) : accent
        } else if isSelected {
            return palette[.text]
        } else if isPast {
            return palette[.text].opacity(0.32)
        } else {
            return palette[.text].opacity(0.62)
        }
    }

    private var weekdayText: String {
        date.formatted(ClinicDate.formatStyle.weekday(.narrow))
    }

    private var dayText: String {
        date.formatted(ClinicDate.formatStyle.day())
    }

    private var accessibilityLabel: String {
        date.formatted(ClinicDate.formatStyle.weekday(.wide).month(.wide).day().year())
    }

    private var accessibilityValue: String {
        [isToday ? "Today" : nil, isSelected ? "Selected" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    @Previewable @State var selectedDate = ClinicDate.today

    WeekDateStrip(selectedDate: $selectedDate, today: ClinicDate.today)
        .background(AppColor.canvas)
}
