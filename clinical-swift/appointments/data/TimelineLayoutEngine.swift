import ClinicalModels
import CoreGraphics
import Foundation

/// Layout Engine for Timeline view
/// Must remain independent of SwiftUI
struct TimelineLayoutEngine {
    let availableWidth: CGFloat
    let scale: TimelineScale
    let overlap: ScheduleCardTuning.Overlap
    let contentMetrics: ScheduleCardContentMetrics
    /// Assert in debug builds if the runtime invariant gate ever triggers fallback.
    let assertOnFallback: Bool

    init(
        availableWidth: CGFloat,
        scale: TimelineScale,
        overlap: ScheduleCardTuning.Overlap = .init(),
        contentMetrics: ScheduleCardContentMetrics = .init(),
        assertOnFallback: Bool = true
    ) {
        self.availableWidth = availableWidth
        self.scale = scale
        self.overlap = overlap
        self.contentMetrics = contentMetrics
        self.assertOnFallback = assertOnFallback
    }

    func layout(
        items: [TimelineItem], floatingID: TimelineItem.ID? = nil
    ) -> [TimelineItemLayoutInfo] {
        // The held card uses the full content width and does not displace other cards.
        let regular = items.filter { $0.id != floatingID }
        let floating = items.filter { $0.id == floatingID }
        var result: [TimelineItemLayoutInfo] = []
        var nextZIndex = 0
        for group in overlappingGroups(for: regular) {
            let groupLayouts = layout(group: group, startingZIndex: nextZIndex)
            nextZIndex += groupLayouts.count
            result.append(contentsOf: groupLayouts)
        }
        for item in floating {
            let rect = CGRect(
                x: scale.metrics.contentLeadingInset,
                y: cardY(for: item),
                width: cardWidth,
                height: cardHeight(for: item)
            )
            let presentation = contentMetrics.resolvePresentation(
                start: item.start,
                label: item.displayLabel,
                cardHeight: rect.height,
                availableWidth: rect.width
            )
            result.append(
                TimelineItemLayoutInfo(
                    id: item.id,
                    item: item,
                    rect: rect,
                    zIndex: nextZIndex,
                    isOverlappingFront: false,
                    contentTrailingInset: 0,
                    presentation: presentation
                )
            )
            nextZIndex += 1
        }
        return result
    }

    private func layout(
        group: [TimelineItem], startingZIndex: Int
    ) -> [TimelineItemLayoutInfo] {
        guard group.count > 1 else {
            return group.enumerated().map { offset, item in
                let rect = CGRect(
                    x: scale.metrics.contentLeadingInset,
                    y: cardY(for: item),
                    width: cardWidth,
                    height: cardHeight(for: item)
                )
                let presentation =
                    overlap.mode == .current
                    ? contentMetrics.defaultPresentation(cardHeight: rect.height)
                    : contentMetrics.resolvePresentation(
                        start: item.start,
                        label: item.displayLabel,
                        cardHeight: rect.height,
                        availableWidth: rect.width
                    )
                return TimelineItemLayoutInfo(
                    id: item.id,
                    item: item,
                    rect: rect,
                    zIndex: startingZIndex + offset,
                    isOverlappingFront: false,
                    contentTrailingInset: 0,
                    presentation: presentation
                )
            }
        }

        switch overlap.mode {
        case .current:
            return layoutLegacyColumns(group: group, startingZIndex: startingZIndex)
        case .cascade, .textAware:
            return layoutEnforcedOverlap(group: group, startingZIndex: startingZIndex)
        }
    }

    /// Legacy non-overlapping column layout used by the `.current` comparison mode.
    private func layoutLegacyColumns(
        group: [TimelineItem], startingZIndex: Int
    ) -> [TimelineItemLayoutInfo] {
        let assignments = columnAssignments(
            for: group.sorted(by: legacyItemSort),
            maximumColumns: Self.maximumOverlappingColumns
        )
        let columnCount = max(
            assignments.map(\.column).max().map { $0 + 1 } ?? 1,
            1
        )
        let width = cardWidth(columnCount: columnCount)

        return assignments.enumerated().map { offset, assignment in
            let item = assignment.item
            let rect = CGRect(
                x: cardX(column: assignment.column, columnWidth: width),
                y: cardY(for: item),
                width: width,
                height: cardHeight(for: item)
            )
            return TimelineItemLayoutInfo(
                id: item.id,
                item: item,
                rect: rect,
                zIndex: startingZIndex + offset,
                isOverlappingFront: false,
                contentTrailingInset: 0,
                presentation: contentMetrics.defaultPresentation(cardHeight: rect.height)
            )
        }
    }

    /// Constraint-driven overlapping layout guarded by an exact 2D invariant validator.
    private func layoutEnforcedOverlap(
        group: [TimelineItem], startingZIndex: Int
    ) -> [TimelineItemLayoutInfo] {
        let bounds = HorizontalSpan(
            min: scale.metrics.contentLeadingInset,
            max: scale.metrics.contentLeadingInset + cardWidth
        )
        guard bounds.width > 0 else {
            return fallbackNonOverlappingColumns(group: group, startingZIndex: startingZIndex)
        }

        let ordered = group.sorted(by: overlapItemSort)
        let prepared = ordered.map { item -> PreparedItem in
            let minY = cardY(for: item)
            let height = cardHeight(for: item)
            let metrics = contentMetrics.bounds(
                start: item.start,
                label: item.displayLabel,
                cardHeight: height,
                presentation: contentMetrics.defaultPresentation(cardHeight: height)
            )
            return PreparedItem(
                item: item,
                minY: minY,
                maxY: minY + height,
                contentBounds: metrics
            )
        }

        if let solved = solveOverlap(items: prepared, bounds: bounds) {
            let entries = buildValidatedEntries(
                from: solved, startingZIndex: startingZIndex)
            let violations = TimelineLayoutValidator.validate(
                entries: entries,
                bounds: bounds,
                stripWidth: CGFloat(overlap.stripWidth)
            )
            if violations.isEmpty {
                return entries.map(\.layoutInfo)
            }
            if assertOnFallback {
                assertionFailure(
                    "Timeline overlapping layout violated invariants: \(violations)")
            }
        }

        return fallbackNonOverlappingColumns(group: group, startingZIndex: startingZIndex)
    }

    /// Guaranteed non-overlapping column layout with no column cap so invariants always hold.
    private func fallbackNonOverlappingColumns(
        group: [TimelineItem], startingZIndex: Int
    ) -> [TimelineItemLayoutInfo] {
        let assignments = columnAssignments(
            for: group.sorted(by: overlapItemSort),
            maximumColumns: nil
        )
        let columnCount = max(
            assignments.map(\.column).max().map { $0 + 1 } ?? 1,
            1
        )
        let width = cardWidth(columnCount: columnCount)

        return assignments.enumerated().map { offset, assignment in
            let item = assignment.item
            let rect = CGRect(
                x: cardX(column: assignment.column, columnWidth: width),
                y: cardY(for: item),
                width: width,
                height: cardHeight(for: item)
            )
            let presentation = contentMetrics.resolvePresentation(
                start: item.start,
                label: item.displayLabel,
                cardHeight: rect.height,
                availableWidth: rect.width
            )
            return TimelineItemLayoutInfo(
                id: item.id,
                item: item,
                rect: rect,
                zIndex: startingZIndex + offset,
                isOverlappingFront: false,
                contentTrailingInset: 0,
                presentation: presentation
            )
        }
    }

    private func solveOverlap(
        items: [PreparedItem],
        bounds: HorizontalSpan
    ) -> [PlacedItem]? {
        let strip = effectiveStripWidth(in: bounds)
        let minimumWidth = min(Self.minimumCardWidth, bounds.width)
        let waves = contentWaves(for: items)

        var placed: [PlacedItem] = []
        placed.reserveCapacity(items.count)

        for wave in waves {
            guard let waveMinY = wave.map(\.minY).min(),
                let waveMaxY = wave.map(\.maxY).max()
            else { continue }

            // Earlier waves start before wave[0], so any earlier item active during this wave
            // is active at waveMinY.
            let activeEarlier = placed.filter { $0.rect.maxY > waveMinY + Self.epsilon }
            let hostSlots = freeHorizontalSpans(
                in: bounds,
                yMin: waveMinY,
                yMax: waveMaxY,
                against: activeEarlier,
                stripWidth: strip
            )

            guard !hostSlots.isEmpty else { return nil }

            if wave.count == 1 {
                let item = wave[0]
                guard let bestSlot = hostSlots.max(by: { $0.width < $1.width }),
                    bestSlot.width >= minimumWidth
                else { return nil }

                placed.append(makePlacedItem(item, span: bestSlot))
                continue
            }

            let waveColumns = contentColumnAssignments(for: wave)
            let columnCount = (waveColumns.max() ?? 0) + 1
            let isClique = columnCount == wave.count

            if isClique {
                let slotCounts = allocateSlots(count: wave.count, across: hostSlots)
                guard let slotCounts else { return nil }

                var itemCursor = 0
                for (slotIndex, count) in slotCounts.enumerated() where count > 0 {
                    let slot = hostSlots[slotIndex]
                    let slice = Array(wave[itemCursor..<(itemCursor + count)])
                    itemCursor += count
                    guard
                        let slicePlaced = placeClique(
                            slice,
                            in: slot,
                            stripWidth: strip,
                            minimumWidth: minimumWidth
                        )
                    else { return nil }
                    placed.append(contentsOf: slicePlaced)
                }
            } else {
                let slotCounts = allocateSlots(count: columnCount, across: hostSlots)
                guard let slotCounts else { return nil }

                var columnSpans: [HorizontalSpan] = []
                for (slotIndex, count) in slotCounts.enumerated() where count > 0 {
                    let slot = hostSlots[slotIndex]
                    let colWidth = slot.width / CGFloat(count)
                    guard colWidth >= minimumWidth else { return nil }
                    for col in 0..<count {
                        let start = slot.min + CGFloat(col) * colWidth
                        columnSpans.append(HorizontalSpan(min: start, max: start + colWidth))
                    }
                }

                for (index, item) in wave.enumerated() {
                    let colSpan = columnSpans[waveColumns[index]]
                    let freeInCol = freeHorizontalSpans(
                        in: colSpan,
                        yMin: item.minY,
                        yMax: item.maxY,
                        against: placed,
                        stripWidth: strip
                    )
                    guard let best = freeInCol.max(by: { $0.width < $1.width }),
                        best.width >= minimumWidth
                    else { return nil }

                    placed.append(makePlacedItem(item, span: best))
                }
            }
        }

        return placed
    }

    private func placeClique(
        _ items: [PreparedItem],
        in slot: HorizontalSpan,
        stripWidth: CGFloat,
        minimumWidth: CGFloat
    ) -> [PlacedItem]? {
        var result: [PlacedItem] = []
        var cursor = slot.min

        for index in items.indices {
            let item = items[index]
            let remaining = items.count - index
            let availableSpan = slot.max - cursor
            guard availableSpan > Self.epsilon else { return nil }

            if remaining == 1 {
                guard availableSpan >= minimumWidth else { return nil }
                let span = HorizontalSpan(min: cursor, max: slot.max)
                result.append(makePlacedItem(item, span: span))
                break
            }

            let fairWidth = availableSpan / CGFloat(remaining)
            guard fairWidth >= minimumWidth else { return nil }

            if overlap.mode == .textAware {
                // Try calmest presentation first: full time -> compact stack (30m) -> compact time.
                let candidates = contentMetrics.candidatePresentations(cardHeight: item.height)

                // Estimate the narrowest readable width needed by the remaining peers in this clique.
                let nextPeerDemands = items[(index + 1)...].map { peer in
                    let peerLayout: ScheduleCardPresentation.Layout =
                        contentMetrics.canCompactStack(cardHeight: peer.height)
                        ? .compactStacked
                        : contentMetrics.defaultLayout(cardHeight: peer.height)
                    return contentMetrics.bounds(
                        start: peer.item.start,
                        label: peer.item.displayLabel,
                        cardHeight: peer.height,
                        presentation: ScheduleCardPresentation(
                            layout: peerLayout, usesCompactTime: false)
                    ).width
                }
                let remainingPeersDemand = nextPeerDemands.reduce(0, +)

                var bestCandidate:
                    (
                        presentation: ScheduleCardPresentation,
                        bounds: ScheduleCardContentMetrics.Bounds, advance: CGFloat
                    )?
                for candidate in candidates {
                    let measured = contentMetrics.bounds(
                        start: item.item.start,
                        label: item.item.displayLabel,
                        cardHeight: item.height,
                        presentation: candidate
                    )
                    // Keep text clear of the next front card.
                    let requiredAdvance = max(measured.width, stripWidth)
                    let remainingAfterOverlap = slot.max - (cursor + requiredAdvance)
                    let nextFairWidth = remainingAfterOverlap / CGFloat(remaining - 1)
                    if requiredAdvance <= fairWidth + Self.epsilon,
                        nextFairWidth >= minimumWidth
                    {
                        if bestCandidate == nil
                            || requiredAdvance < (bestCandidate?.advance ?? .infinity)
                                - Self.epsilon
                        {
                            bestCandidate = (candidate, measured, requiredAdvance)
                        }
                        // Stop at the calmest option as soon as remaining peers fit untruncated.
                        if remainingAfterOverlap + Self.epsilon >= remainingPeersDemand {
                            break
                        }
                    }
                }
                if let chosen = bestCandidate {
                    let span = HorizontalSpan(min: cursor, max: slot.max)
                    result.append(
                        makePlacedItem(
                            item,
                            span: span,
                            presentation: chosen.presentation,
                            contentBoundsOverride: chosen.bounds
                        )
                    )
                    cursor += chosen.advance
                    continue
                }
            }

            let span = HorizontalSpan(min: cursor, max: cursor + fairWidth)
            result.append(makePlacedItem(item, span: span))
            cursor += fairWidth
        }

        return result
    }

    private func buildValidatedEntries(
        from placed: [PlacedItem],
        startingZIndex: Int
    ) -> [ValidatedLayoutEntry] {
        placed.indices.map { index in
            let current = placed[index]
            let isOverlappingFront = placed[0..<index].contains { lower in
                rectsOverlap(current.rect, lower.rect)
            }

            // Fence content away from any front card that overlaps this card's vertical content band.
            var nearestFrontLeft = current.rect.maxX
            for upperIndex in (index + 1)..<placed.count {
                let upper = placed[upperIndex]
                let verticallyHitsContent =
                    upper.rect.minY < current.contentRect.maxY - Self.epsilon
                    && current.contentRect.minY < upper.rect.maxY - Self.epsilon
                if verticallyHitsContent, upper.rect.minX > current.rect.minX + Self.epsilon {
                    nearestFrontLeft = min(nearestFrontLeft, upper.rect.minX)
                }
            }

            let contentTrailingInset: CGFloat
            if nearestFrontLeft < current.rect.maxX - Self.epsilon {
                // Leave 4 pt breathing room before the front card.
                contentTrailingInset = max(
                    0, current.rect.maxX - (nearestFrontLeft - Self.contentFenceGap))
            } else {
                contentTrailingInset = 0
            }

            let availableContentWidth = max(nearestFrontLeft - current.rect.minX, 0)
            let presentation = contentMetrics.resolvePresentation(
                start: current.item.start,
                label: current.item.displayLabel,
                cardHeight: current.rect.height,
                availableWidth: availableContentWidth,
                minimum: current.presentation
            )
            let info = TimelineItemLayoutInfo(
                id: current.item.id,
                item: current.item,
                rect: current.rect,
                zIndex: startingZIndex + index,
                isOverlappingFront: isOverlappingFront,
                contentTrailingInset: contentTrailingInset,
                presentation: presentation
            )
            let resolvedBounds = contentMetrics.bounds(
                start: current.item.start,
                label: current.item.displayLabel,
                cardHeight: current.rect.height,
                presentation: presentation
            )
            let protectedWidth: CGFloat =
                switch overlap.mode {
                case .textAware:
                    min(current.rect.width, resolvedBounds.width)
                case .cascade, .current:
                    current.rect.width
                }
            let validatedContentRect = CGRect(
                x: current.rect.minX,
                y: current.rect.minY,
                width: protectedWidth,
                height: min(current.rect.height, resolvedBounds.height)
            )
            return ValidatedLayoutEntry(layoutInfo: info, contentRect: validatedContentRect)
        }
    }

    private func makePlacedItem(
        _ prepared: PreparedItem,
        span: HorizontalSpan,
        presentation: ScheduleCardPresentation? = nil,
        contentBoundsOverride: ScheduleCardContentMetrics.Bounds? = nil
    ) -> PlacedItem {
        let rect = prepared.rect(in: span)
        let resolvedPresentation =
            presentation ?? contentMetrics.defaultPresentation(cardHeight: rect.height)
        let bounds = contentBoundsOverride ?? prepared.contentBounds
        let protectedWidth: CGFloat =
            switch overlap.mode {
            case .textAware:
                min(rect.width, bounds.width)
            case .cascade, .current:
                rect.width
            }
        let contentRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: protectedWidth,
            height: min(rect.height, bounds.height)
        )
        return PlacedItem(
            item: prepared.item,
            rect: rect,
            contentRect: contentRect,
            presentation: resolvedPresentation
        )
    }

    /// Split a time-overlapping group into sequential waves whose content bands do not collide.
    private func contentWaves(for items: [PreparedItem]) -> [[PreparedItem]] {
        var waves: [[PreparedItem]] = []
        var currentWave: [PreparedItem] = []
        var currentMaxContentEnd: CGFloat?

        for item in items {
            let contentEnd = item.minY + item.contentBounds.height
            if let maxEnd = currentMaxContentEnd,
                item.minY >= maxEnd - Self.epsilon
            {
                waves.append(currentWave)
                currentWave = [item]
                currentMaxContentEnd = contentEnd
            } else {
                currentWave.append(item)
                currentMaxContentEnd = max(currentMaxContentEnd ?? contentEnd, contentEnd)
            }
        }
        if !currentWave.isEmpty {
            waves.append(currentWave)
        }
        return waves
    }

    /// Assign minimal side-by-side columns based only on vertical content-band collisions.
    private func contentColumnAssignments(for items: [PreparedItem]) -> [Int] {
        var columnContentEnds: [CGFloat] = []
        return items.map { item in
            let contentEnd = item.minY + item.contentBounds.height
            if let reusable = columnContentEnds.firstIndex(where: {
                $0 <= item.minY + Self.epsilon
            }) {
                columnContentEnds[reusable] = contentEnd
                return reusable
            }
            let column = columnContentEnds.count
            columnContentEnds.append(contentEnd)
            return column
        }
    }

    /// Distribute `count` columns across available host slots to maximize minimum column width.
    private func allocateSlots(
        count: Int,
        across slots: [HorizontalSpan]
    ) -> [Int]? {
        guard count > 0, !slots.isEmpty else { return nil }
        var counts = Array(repeating: 0, count: slots.count)
        for _ in 0..<count {
            var bestIndex: Int?
            var bestWidth: CGFloat = -1
            for index in slots.indices {
                let nextCount = counts[index] + 1
                let width = slots[index].width / CGFloat(nextCount)
                if width > bestWidth {
                    bestWidth = width
                    bestIndex = index
                }
            }
            guard let chosen = bestIndex, bestWidth > 0 else { return nil }
            counts[chosen] += 1
        }
        return counts
    }

    private func freeHorizontalSpans(
        in container: HorizontalSpan,
        yMin: CGFloat,
        yMax: CGFloat,
        against placed: [PlacedItem],
        stripWidth: CGFloat
    ) -> [HorizontalSpan] {
        var forbidden: [HorizontalSpan] = []

        for lower in placed {
            let overlapsVertically =
                lower.rect.minY < yMax - Self.epsilon
                && yMin < lower.rect.maxY - Self.epsilon
            if overlapsVertically {
                // Keep every overlapped lower card's continuous left strip uncovered.
                let stripEnd = min(lower.rect.minX + stripWidth, lower.rect.maxX)
                forbidden.append(HorizontalSpan(min: lower.rect.minX, max: stripEnd))
            }

            let overlapsContentVertically =
                lower.contentRect.minY < yMax - Self.epsilon
                && yMin < lower.contentRect.maxY - Self.epsilon
            if overlapsContentVertically {
                forbidden.append(
                    HorizontalSpan(min: lower.contentRect.minX, max: lower.contentRect.maxX))
            }
        }

        return subtract(forbidden, from: container)
    }

    private func subtract(
        _ forbidden: [HorizontalSpan], from container: HorizontalSpan
    ) -> [HorizontalSpan] {
        let clamped = forbidden.compactMap { span -> HorizontalSpan? in
            let start = max(span.min, container.min)
            let end = min(span.max, container.max)
            return end > start + Self.epsilon ? HorizontalSpan(min: start, max: end) : nil
        }.sorted { $0.min < $1.min }

        guard !clamped.isEmpty else {
            return container.width > Self.epsilon ? [container] : []
        }

        var merged: [HorizontalSpan] = []
        for span in clamped {
            if let last = merged.last, span.min <= last.max + Self.epsilon {
                merged[merged.count - 1] = HorizontalSpan(
                    min: last.min, max: max(last.max, span.max))
            } else {
                merged.append(span)
            }
        }

        var free: [HorizontalSpan] = []
        var cursor = container.min
        for blocked in merged {
            if blocked.min > cursor + Self.epsilon {
                free.append(HorizontalSpan(min: cursor, max: blocked.min))
            }
            cursor = max(cursor, blocked.max)
        }
        if container.max > cursor + Self.epsilon {
            free.append(HorizontalSpan(min: cursor, max: container.max))
        }
        return free
    }

    private func rectsOverlap(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let intersection = lhs.intersection(rhs)
        return !intersection.isNull
            && intersection.width > Self.epsilon
            && intersection.height > Self.epsilon
    }

    private func effectiveStripWidth(in bounds: HorizontalSpan) -> CGFloat {
        min(max(CGFloat(overlap.stripWidth), 0), bounds.width)
    }

    private var cardWidth: CGFloat {
        scale.metrics.contentWidth(availableWidth: availableWidth)
    }

    private func cardWidth(columnCount: Int) -> CGFloat {
        guard columnCount > 1 else {
            return cardWidth
        }

        let spacing = scale.metrics.overlapColumnSpacing * CGFloat(columnCount - 1)
        return max((cardWidth - spacing) / CGFloat(columnCount), 0)
    }

    private func cardHeight(for item: TimelineItem) -> CGFloat {
        max(
            scale.height(
                from: item.start.timeOfDay,
                to: item.start.timeOfDay + item.durationMinutes
            )
                // 2x to account for top and bottom clearance both
                - scale.metrics.verticalCardMargin * 2,
            0
        )
    }

    private func cardX(column: Int, columnWidth: CGFloat) -> CGFloat {
        scale.metrics.contentLeadingInset
            + CGFloat(column) * (columnWidth + scale.metrics.overlapColumnSpacing)
    }

    private func cardY(for item: TimelineItem) -> CGFloat {
        return scale.yOffset(for: item.start.timeOfDay)
            + scale.metrics.verticalCardMargin
    }

    private func overlappingGroups(
        for items: [TimelineItem]
    ) -> [[TimelineItem]] {
        let sortedItems = items.sorted(by: legacyItemSort)
        var groups: [[TimelineItem]] = []
        var currentGroup: [TimelineItem] = []
        var currentGroupEndMinute: Int?

        for item in sortedItems {
            let startMinute = startMinute(for: item)
            let endMinute = endMinute(for: item)

            if let groupEndMinute = currentGroupEndMinute,
                startMinute >= groupEndMinute
            {
                groups.append(currentGroup)
                currentGroup = [item]
                currentGroupEndMinute = endMinute
            } else {
                currentGroup.append(item)
                currentGroupEndMinute = max(currentGroupEndMinute ?? endMinute, endMinute)
            }
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups
    }

    private func columnAssignments(
        for items: [TimelineItem],
        maximumColumns: Int?
    ) -> [TimelineItemColumnAssignment] {
        var columnEndMinutes: [Int] = []

        return items.map { item in
            let startMinute = startMinute(for: item)
            let endMinute = endMinute(for: item)
            let column: Int

            if let reusableColumn = columnEndMinutes.firstIndex(where: {
                $0 <= startMinute
            }) {
                column = reusableColumn
                columnEndMinutes[reusableColumn] = endMinute
            } else if maximumColumns == nil || columnEndMinutes.count < (maximumColumns ?? 0) {
                column = columnEndMinutes.count
                columnEndMinutes.append(endMinute)
            } else {
                column = (maximumColumns ?? 1) - 1
                columnEndMinutes[column] = max(columnEndMinutes[column], endMinute)
            }

            return TimelineItemColumnAssignment(
                item: item,
                column: column
            )
        }
    }

    private func legacyItemSort(
        lhs: TimelineItem,
        rhs: TimelineItem
    ) -> Bool {
        let lhsStart = startMinute(for: lhs)
        let rhsStart = startMinute(for: rhs)
        if lhsStart != rhsStart {
            return lhsStart < rhsStart
        }

        let lhsEnd = endMinute(for: lhs)
        let rhsEnd = endMinute(for: rhs)
        if lhsEnd != rhsEnd {
            return lhsEnd < rhsEnd
        }

        return lhs.id.sortKey < rhs.id.sortKey
    }

    /// Earlier start goes behind later start; for equal starts, longer duration goes behind.
    private func overlapItemSort(
        lhs: TimelineItem,
        rhs: TimelineItem
    ) -> Bool {
        let lhsStart = startMinute(for: lhs)
        let rhsStart = startMinute(for: rhs)
        if lhsStart != rhsStart {
            return lhsStart < rhsStart
        }

        let lhsEnd = endMinute(for: lhs)
        let rhsEnd = endMinute(for: rhs)
        if lhsEnd != rhsEnd {
            return lhsEnd > rhsEnd
        }

        return lhs.id.sortKey < rhs.id.sortKey
    }

    private func startMinute(for item: TimelineItem) -> Int {
        item.start.timeOfDay.minutes(since: Bitehaus.opening)
    }

    private func endMinute(for item: TimelineItem) -> Int {
        startMinute(for: item) + item.durationMinutes
    }

    private static let maximumOverlappingColumns = 3
    private static let minimumCardWidth: CGFloat = 52
    private static let contentFenceGap: CGFloat = 4
    private static let epsilon: CGFloat = 0.001
}

struct TimelineItemLayoutInfo: Identifiable {
    let id: TimelineItem.ID
    let item: TimelineItem
    let rect: CGRect
    let zIndex: Int
    let isOverlappingFront: Bool
    let contentTrailingInset: CGFloat
    let presentation: ScheduleCardPresentation

    var usesCompactTime: Bool { presentation.usesCompactTime }
    var usesCompactStack: Bool { presentation.layout == .compactStacked }

    init(
        id: TimelineItem.ID,
        item: TimelineItem,
        rect: CGRect,
        zIndex: Int = 0,
        isOverlappingFront: Bool = false,
        contentTrailingInset: CGFloat = 0,
        presentation: ScheduleCardPresentation = .init()
    ) {
        self.id = id
        self.item = item
        self.rect = rect
        self.zIndex = zIndex
        self.isOverlappingFront = isOverlappingFront
        self.contentTrailingInset = contentTrailingInset
        self.presentation = presentation
    }
}

private struct PreparedItem {
    let item: TimelineItem
    let minY: CGFloat
    let maxY: CGFloat
    let contentBounds: ScheduleCardContentMetrics.Bounds

    var height: CGFloat { max(maxY - minY, 0) }

    func rect(in span: HorizontalSpan) -> CGRect {
        CGRect(x: span.min, y: minY, width: span.width, height: height)
    }
}

private struct PlacedItem {
    let item: TimelineItem
    let rect: CGRect
    let contentRect: CGRect
    let presentation: ScheduleCardPresentation
}

private struct TimelineItemColumnAssignment {
    let item: TimelineItem
    let column: Int
}
