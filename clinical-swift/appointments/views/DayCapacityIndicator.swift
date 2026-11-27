import ClinicalModels
import SwiftUI

nonisolated enum DayCapacitySettings {
    static let showIndicatorsKey = "schedule.showDayCapacityIndicators"
}

/// Lightweight appointment time span within a clinic day, measured in minutes since midnight.
nonisolated struct DayCapacitySlot: Equatable, Sendable {
    let startMinute: Int
    let endMinute: Int

    init(startMinute: Int, endMinute: Int) {
        let clampedStart = min(max(startMinute, 0), 24 * 60)
        let clampedEnd = min(max(endMinute, clampedStart), 24 * 60)
        self.startMinute = clampedStart
        self.endMinute = clampedEnd
    }

    init(start: Date, durationMinutes: Int, calendar: Calendar = ClinicDate.calendar) {
        let startTime = TimeOfDay(date: start, calendar: calendar).totalMinutes
        self.init(startMinute: startTime, endMinute: startTime + max(durationMinutes, 0))
    }
}

/// Computes merged occupied appointment spans and drawn pill intervals for morning/evening shifts.
nonisolated struct DayCapacityMetrics: Equatable, Sendable {
    static let morningRange = Bitehaus.opening.totalMinutes..<Bitehaus.break.start.totalMinutes
    static let eveningRange = Bitehaus.break.end.totalMinutes..<Bitehaus.closing.totalMinutes

    let slots: [DayCapacitySlot]

    /// Merges contiguous and overlapping appointments into occupied spans clipped to `range`.
    func mergedSpans(in range: Range<Int>) -> [Range<Int>] {
        let clipped =
            slots
            .compactMap { slot -> Range<Int>? in
                let start = max(slot.startMinute, range.lowerBound)
                let end = min(slot.endMinute, range.upperBound)
                return end > start ? start..<end : nil
            }
            .sorted { $0.lowerBound < $1.lowerBound }

        var merged: [Range<Int>] = []
        for span in clipped {
            if let last = merged.last, span.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, span.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// Maps merged spans in `range` onto horizontal pill intervals within `0...width`,
    /// coalescing pills that would visually collide after applying `minPillWidth`.
    func pillIntervals(
        in range: Range<Int>,
        width: CGFloat,
        minPillWidth: CGFloat
    ) -> [ClosedRange<CGFloat>] {
        let total = CGFloat(range.upperBound - range.lowerBound)
        guard total > 0, width > 0 else { return [] }

        let raw: [ClosedRange<CGFloat>] = mergedSpans(in: range).map { span in
            let startFraction = CGFloat(span.lowerBound - range.lowerBound) / total
            let endFraction = CGFloat(span.upperBound - range.lowerBound) / total
            let spanWidth = (endFraction - startFraction) * width
            let pillWidth = min(max(spanWidth, minPillWidth), width)
            let center = ((startFraction + endFraction) / 2) * width
            let startX = min(max(center - pillWidth / 2, 0), width - pillWidth)
            return startX...min(startX + pillWidth, width)
        }

        // Coalesce adjacent pills that overlap visually after minimum-width expansion so an
        // edge-clamped short pill never mashes into its neighbor with a flat-looking side.
        var coalesced: [ClosedRange<CGFloat>] = []
        for interval in raw {
            if let last = coalesced.last, interval.lowerBound <= last.upperBound + 0.25 {
                coalesced[coalesced.count - 1] =
                    last.lowerBound...max(last.upperBound, interval.upperBound)
            } else {
                coalesced.append(interval)
            }
        }
        return coalesced
    }
}

/// Split morning/evening hairline with duration-scaled micro-pills for one day in `WeekDateStrip`.
/// Appointments inside the 1:00–4:00 PM clinic break are intentionally ignored.
struct DayCapacityIndicatorView: View {
    @Environment(\.appPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    let slots: [DayCapacitySlot]
    let isToday: Bool
    let isSelected: Bool
    let isPast: Bool

    private static let indicatorWidth: CGFloat = 34
    private static let indicatorHeight: CGFloat = 6
    private static let breakGap: CGFloat = 3.5
    private static let lineHeight: CGFloat = 1.1
    private static let pillHeight: CGFloat = 4.2
    private static let minPillWidth: CGFloat = 2.8

    var body: some View {
        let metrics = DayCapacityMetrics(slots: slots)
        let fill = resolvedFillColor
        let line = resolvedLineColor

        Canvas { context, size in
            let usableWidth = size.width - Self.breakGap
            let morningWidth = usableWidth * (4.0 / 9.0)
            let eveningWidth = usableWidth * (5.0 / 9.0)
            let eveningStartX = morningWidth + Self.breakGap
            let centerY = size.height / 2

            drawShift(
                intervals: metrics.pillIntervals(
                    in: DayCapacityMetrics.morningRange,
                    width: morningWidth,
                    minPillWidth: Self.minPillWidth
                ),
                startX: 0,
                width: morningWidth,
                centerY: centerY,
                lineColor: line,
                fillColor: fill,
                in: &context
            )
            drawShift(
                intervals: metrics.pillIntervals(
                    in: DayCapacityMetrics.eveningRange,
                    width: eveningWidth,
                    minPillWidth: Self.minPillWidth
                ),
                startX: eveningStartX,
                width: eveningWidth,
                centerY: centerY,
                lineColor: line,
                fillColor: fill,
                in: &context
            )
        }
        .frame(width: Self.indicatorWidth, height: Self.indicatorHeight)
        .allowsHitTesting(false)
    }

    /// Matches the day cell's exact color hierarchy: accent on Today, crisp neutral on upcoming
    /// or selected dates, and de-emphasized neutral on unselected past dates.
    private var resolvedFillColor: Color {
        let isDark = colorScheme == .dark
        if isToday {
            let accent = palette.opaqueAccent(in: environment)
            return isSelected ? palette.todaySelection.textColor(accent: accent) : accent
        } else if isSelected {
            return palette[.text].opacity(0.82)
        } else if isPast {
            return palette[.text].opacity(isDark ? 0.34 : 0.32)
        } else {
            return palette[.text].opacity(isDark ? 0.68 : 0.62)
        }
    }

    private var resolvedLineColor: Color {
        let isDark = colorScheme == .dark
        let isDimmedPast = isPast && !isSelected
        return isDimmedPast
            ? palette[.text].opacity(isDark ? 0.14 : 0.09)
            : palette[.text].opacity(isDark ? 0.22 : 0.15)
    }

    private func drawShift(
        intervals: [ClosedRange<CGFloat>],
        startX: CGFloat,
        width: CGFloat,
        centerY: CGFloat,
        lineColor: Color,
        fillColor: Color,
        in context: inout GraphicsContext
    ) {
        let lineRect = CGRect(
            x: startX,
            y: centerY - Self.lineHeight / 2,
            width: width,
            height: Self.lineHeight
        )
        context.fill(capsulePath(lineRect), with: .color(lineColor))

        for interval in intervals {
            let pillRect = CGRect(
                x: startX + interval.lowerBound,
                y: centerY - Self.pillHeight / 2,
                width: interval.upperBound - interval.lowerBound,
                height: Self.pillHeight
            )
            context.fill(capsulePath(pillRect), with: .color(fillColor))
        }
    }

    private func capsulePath(_ rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2, style: .circular)
    }
}
