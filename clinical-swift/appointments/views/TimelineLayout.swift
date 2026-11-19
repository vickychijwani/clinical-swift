import ClinicalModels
import CoreGraphics
import Foundation

/// Layout Engine for Timeline view
/// Must remain independent of SwiftUI

struct TimelineMetrics {
    /// Height of 1 hour in pixels
    let hourHeight: CGFloat

    /// Width of time labels in left column of timeline
    let timeColumnWidth: CGFloat

    /// Padding above timeline
    let verticalPadding: CGFloat

    /// Margin left/right of appointment card, relative to hour marker lines
    let horizontalCardMargin: CGFloat

    /// Margin above/below an appointment card, to separate edges clearly from hour markers
    let verticalCardMargin: CGFloat

    /// Horizontal spacing between appointments that overlap in time
    let overlapColumnSpacing: CGFloat

    /// Height used to represent the clinic break when it is compact
    let compactBreakHeight: CGFloat

    var contentLeadingInset: CGFloat {
        timeColumnWidth + horizontalCardMargin + 4
    }

    func contentWidth(availableWidth: CGFloat) -> CGFloat {
        max(
            availableWidth
                - timeColumnWidth
                - horizontalCardMargin * 2, 0)
    }

    /// Number of vertical pixels representing 1 minute
    fileprivate var pixelsPerMinute: CGFloat {
        hourHeight / 60
    }
}

struct TimelineScale {
    enum BreakPresentation {
        case compact
        case expanded
    }

    let breakPresentation: BreakPresentation

    init(items: [TimelineItem], breakPresentation: BreakPresentation? = nil) {
        if let breakPresentation {
            self.breakPresentation = breakPresentation
            return
        }
        self.breakPresentation =
            items.contains { item in
                (Bitehaus.break.start..<Bitehaus.break.end).contains(
                    item.start.timeOfDay
                )
            } ? .expanded : .compact
    }

    var isBreakExpanded: Bool {
        breakPresentation == .expanded
    }

    var breakHeight: CGFloat {
        switch breakPresentation {
        case .compact:
            Timeline.metrics.compactBreakHeight
        case .expanded:
            (Bitehaus.break.start..<Bitehaus.break.end).px
        }
    }

    var totalHeight: CGFloat {
        yOffset(for: Bitehaus.closing)
    }

    var hourMarkers: [TimeOfDay] {
        (Bitehaus.opening.hour...Bitehaus.closing.hour)
            .map { TimeOfDay($0, 0) }
            .filter { time in
                isBreakExpanded
                    || time <= Bitehaus.break.start
                    || time >= Bitehaus.break.end
            }
    }

    /// Content coordinate excluding Timeline's outer vertical padding.
    func yOffset(for proposedTime: TimeOfDay) -> CGFloat {
        let time = min(max(proposedTime, Bitehaus.opening), Bitehaus.closing)
        let firstSegmentHeight = Bitehaus.break.start.minutes(since: Bitehaus.opening).px

        if time <= Bitehaus.break.start {
            return time.minutes(since: Bitehaus.opening).px
        }

        if time < Bitehaus.break.end {
            let elapsedBreakMinutes = time.minutes(since: Bitehaus.break.start)
            let breakDurationMinutes = Bitehaus.break.end.minutes(since: Bitehaus.break.start)
            let breakProgress = CGFloat(elapsedBreakMinutes) / CGFloat(breakDurationMinutes)

            return firstSegmentHeight + breakHeight * breakProgress
        }

        return firstSegmentHeight
            + breakHeight
            + time.minutes(since: Bitehaus.break.end).px
    }

    func height(from start: TimeOfDay, to end: TimeOfDay) -> CGFloat {
        max(yOffset(for: end) - yOffset(for: start), 0)
    }

    /// Invert the same piecewise scale used to draw cards, including compact break minutes.
    func time(at proposedY: CGFloat) -> TimeOfDay {
        let y = min(max(proposedY, 0), totalHeight)
        let breakY = yOffset(for: Bitehaus.break.start)
        let minutes: CGFloat
        if y <= breakY {
            minutes = y / Timeline.metrics.hourHeight * 60
        } else if y < breakY + breakHeight {
            minutes =
                CGFloat(Bitehaus.break.start.minutes(since: Bitehaus.opening))
                + (y - breakY) / breakHeight
                * CGFloat(Bitehaus.break.end.minutes(since: Bitehaus.break.start))
        } else {
            minutes =
                CGFloat(Bitehaus.break.end.minutes(since: Bitehaus.opening))
                + (y - breakY - breakHeight) / Timeline.metrics.hourHeight * 60
        }
        return Bitehaus.opening + Int(minutes.rounded())
    }

    func showsTime(_ time: TimeOfDay) -> Bool {
        guard (Bitehaus.opening..<Bitehaus.closing).contains(time) else {
            return false
        }

        return isBreakExpanded
            || !(Bitehaus.break.start..<Bitehaus.break.end).contains(time)
    }
}

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
            result.append(
                TimelineItemLayoutInfo(
                    id: item.id,
                    item: item,
                    rect: CGRect(
                        x: Timeline.metrics.contentLeadingInset,
                        y: cardY(for: item),
                        width: cardWidth,
                        height: cardHeight(for: item)
                    ),
                    zIndex: nextZIndex,
                    isOverlappingFront: false,
                    contentTrailingInset: 0
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
                TimelineItemLayoutInfo(
                    id: item.id,
                    item: item,
                    rect: CGRect(
                        x: Timeline.metrics.contentLeadingInset,
                        y: cardY(for: item),
                        width: cardWidth,
                        height: cardHeight(for: item)
                    ),
                    zIndex: startingZIndex + offset,
                    isOverlappingFront: false,
                    contentTrailingInset: 0
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
                contentTrailingInset: 0
            )
        }
    }

    /// Constraint-driven overlapping layout guarded by an exact 2D invariant validator.
    private func layoutEnforcedOverlap(
        group: [TimelineItem], startingZIndex: Int
    ) -> [TimelineItemLayoutInfo] {
        let bounds = HorizontalSpan(
            min: Timeline.metrics.contentLeadingInset,
            max: Timeline.metrics.contentLeadingInset + cardWidth
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
                cardHeight: height
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
                overlap: overlap
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
            let presentation = resolveCardPresentation(
                item: item,
                cardHeight: rect.height,
                availableWidth: rect.width,
                requiredCompactTime: false,
                requiredCompactStack: false
            )
            return TimelineItemLayoutInfo(
                id: item.id,
                item: item,
                rect: rect,
                zIndex: startingZIndex + offset,
                isOverlappingFront: false,
                contentTrailingInset: 0,
                usesCompactTime: presentation.usesCompactTime,
                usesCompactStack: presentation.usesCompactStack
            )
        }
    }

    private func solveOverlap(
        items: [PreparedItem],
        bounds: HorizontalSpan
    ) -> [PlacedItem]? {
        let halo = haloMargin
        let strip = effectiveStripWidth(in: bounds)
        let minimumWidth = min(Self.minimumCardWidth, bounds.width)
        let waves = contentWaves(for: items, halo: halo)

        var placed: [PlacedItem] = []
        placed.reserveCapacity(items.count)

        for wave in waves {
            guard let waveMinY = wave.map(\.minY).min(),
                let waveMaxY = wave.map(\.maxY).max()
            else { continue }

            // Earlier waves start before wave[0], so any earlier item active during this wave
            // is active at waveMinY.
            let activeEarlier = placed.filter { $0.rect.maxY > waveMinY + Self.epsilon }
            let hasEarlierOverlap = !activeEarlier.isEmpty
            let hostSlots = freeHorizontalSpans(
                in: bounds,
                yMin: waveMinY,
                yMax: waveMaxY,
                against: activeEarlier,
                stripWidth: strip,
                halo: halo,
                candidateDrawsHalo: hasEarlierOverlap
            )

            guard !hostSlots.isEmpty else { return nil }

            if wave.count == 1 {
                let item = wave[0]
                guard let bestSlot = hostSlots.max(by: { $0.width < $1.width }),
                    bestSlot.width >= minimumWidth
                else { return nil }

                placed.append(
                    makePlacedItem(
                        item,
                        span: bestSlot,
                        drawsHalo: overlapsAny(
                            rect: item.rect(in: bestSlot), placed: placed)
                    )
                )
                continue
            }

            let waveHalo = hasEarlierOverlap ? halo : 0
            let waveColumns = contentColumnAssignments(for: wave, halo: waveHalo)
            let columnCount = (waveColumns.max() ?? 0) + 1
            let isClique = columnCount == wave.count

            if isClique {
                let slotCounts = allocateSlots(
                    count: wave.count, across: hostSlots,
                    columnGap: hasEarlierOverlap ? halo : 0)
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
                            hasEarlierOverlap: hasEarlierOverlap,
                            stripWidth: strip,
                            halo: halo,
                            minimumWidth: minimumWidth,
                            existingPlaced: placed
                        )
                    else { return nil }
                    placed.append(contentsOf: slicePlaced)
                }
            } else {
                let slotCounts = allocateSlots(
                    count: columnCount, across: hostSlots,
                    columnGap: hasEarlierOverlap ? halo : 0)
                guard let slotCounts else { return nil }

                var columnSpans: [HorizontalSpan] = []
                let columnGap = hasEarlierOverlap ? halo : 0
                for (slotIndex, count) in slotCounts.enumerated() where count > 0 {
                    let slot = hostSlots[slotIndex]
                    let totalGap = columnGap * CGFloat(count - 1)
                    let colWidth = (slot.width - totalGap) / CGFloat(count)
                    guard colWidth >= minimumWidth else { return nil }
                    for col in 0..<count {
                        let start = slot.min + CGFloat(col) * (colWidth + columnGap)
                        columnSpans.append(HorizontalSpan(min: start, max: start + colWidth))
                    }
                }

                for (index, item) in wave.enumerated() {
                    let colSpan = columnSpans[waveColumns[index]]
                    let candidateRect = item.rect(in: colSpan)
                    let candidateDrawsHalo = overlapsAny(rect: candidateRect, placed: placed)
                    let freeInCol = freeHorizontalSpans(
                        in: colSpan,
                        yMin: item.minY,
                        yMax: item.maxY,
                        against: placed,
                        stripWidth: strip,
                        halo: halo,
                        candidateDrawsHalo: candidateDrawsHalo
                    )
                    guard let best = freeInCol.max(by: { $0.width < $1.width }),
                        best.width >= minimumWidth
                    else { return nil }

                    placed.append(
                        makePlacedItem(
                            item,
                            span: best,
                            drawsHalo: overlapsAny(rect: item.rect(in: best), placed: placed)
                        )
                    )
                }
            }
        }

        return placed
    }

    private func placeClique(
        _ items: [PreparedItem],
        in slot: HorizontalSpan,
        hasEarlierOverlap: Bool,
        stripWidth: CGFloat,
        halo: CGFloat,
        minimumWidth: CGFloat,
        existingPlaced: [PlacedItem]
    ) -> [PlacedItem]? {
        var result: [PlacedItem] = []
        var cursor = slot.min
        var hasBackgroundOverlap = hasEarlierOverlap

        for index in items.indices {
            let item = items[index]
            let remaining = items.count - index
            let availableSpan = slot.max - cursor
            guard availableSpan > Self.epsilon else { return nil }
            let peerGap = hasBackgroundOverlap ? halo : 0

            if remaining == 1 {
                guard availableSpan >= minimumWidth else { return nil }
                let span = HorizontalSpan(min: cursor, max: slot.max)
                let drawsHalo =
                    hasBackgroundOverlap
                    || overlapsAny(rect: item.rect(in: span), placed: existingPlaced + result)
                result.append(makePlacedItem(item, span: span, drawsHalo: drawsHalo))
                break
            }

            let fairWidth =
                (availableSpan - peerGap * CGFloat(remaining - 1)) / CGFloat(remaining)
            guard fairWidth >= minimumWidth else { return nil }

            if overlap.mode == .textAware {
                // Try calmest presentation first: full time -> compact stack (30m) -> compact time.
                let canCompactStack = contentMetrics.canCompactStack(cardHeight: item.height)
                var candidates: [(compactTime: Bool, compactStack: Bool)] = [(false, false)]
                if canCompactStack {
                    candidates.append((false, true))
                }
                candidates.append((true, canCompactStack))

                // Estimate the narrowest readable width needed by the remaining peers in this clique.
                let nextPeerDemands = items[(index + 1)...].map { peer in
                    let peerCompactStack = contentMetrics.canCompactStack(cardHeight: peer.height)
                    return contentMetrics.bounds(
                        start: peer.item.start,
                        label: peer.item.displayLabel,
                        cardHeight: peer.height,
                        usesCompactTime: false,
                        usesCompactStack: peerCompactStack
                    ).width
                }
                let remainingPeersDemand =
                    nextPeerDemands.reduce(0, +) + halo * CGFloat(max(remaining - 2, 0))

                var bestCandidate:
                    (
                        compactTime: Bool, compactStack: Bool,
                        bounds: ScheduleCardContentMetrics.Bounds, advance: CGFloat
                    )?
                for candidate in candidates {
                    let measured = contentMetrics.bounds(
                        start: item.item.start,
                        label: item.item.displayLabel,
                        cardHeight: item.height,
                        usesCompactTime: candidate.compactTime,
                        usesCompactStack: candidate.compactStack
                    )
                    // Keep text clear of the next front card and its outer halo.
                    let requiredAdvance = max(measured.width + halo, stripWidth)
                    let remainingAfterOverlap = slot.max - (cursor + requiredAdvance)
                    let nextFairWidth =
                        (remainingAfterOverlap - halo * CGFloat(remaining - 2))
                        / CGFloat(remaining - 1)
                    if requiredAdvance <= fairWidth + Self.epsilon,
                        nextFairWidth >= minimumWidth
                    {
                        if bestCandidate == nil || requiredAdvance < (bestCandidate?.advance ?? .infinity) - Self.epsilon {
                            bestCandidate = (
                                candidate.compactTime, candidate.compactStack, measured,
                                requiredAdvance
                            )
                        }
                        // Stop at the calmest option as soon as remaining peers fit untruncated.
                        if remainingAfterOverlap + Self.epsilon >= remainingPeersDemand {
                            break
                        }
                    }
                }
                if let chosen = bestCandidate {
                    let span = HorizontalSpan(min: cursor, max: slot.max)
                    let drawsHalo =
                        hasBackgroundOverlap
                        || overlapsAny(
                            rect: item.rect(in: span), placed: existingPlaced + result)
                    result.append(
                        makePlacedItem(
                            item,
                            span: span,
                            drawsHalo: drawsHalo,
                            usesCompactTime: chosen.compactTime,
                            usesCompactStack: chosen.compactStack,
                            contentBoundsOverride: chosen.bounds
                        )
                    )
                    cursor += chosen.advance
                    hasBackgroundOverlap = true
                    continue
                }
            }

            let span = HorizontalSpan(min: cursor, max: cursor + fairWidth)
            let drawsHalo =
                hasBackgroundOverlap
                || overlapsAny(rect: item.rect(in: span), placed: existingPlaced + result)
            result.append(makePlacedItem(item, span: span, drawsHalo: drawsHalo))
            cursor += fairWidth + peerGap
        }

        return result
    }

    private func buildValidatedEntries(
        from placed: [PlacedItem],
        startingZIndex: Int
    ) -> [ValidatedLayoutEntry] {
        let halo = haloMargin
        return placed.indices.map { index in
            let current = placed[index]
            let isOverlappingFront = placed[0..<index].contains { lower in
                rectsOverlap(current.rect, lower.rect)
            }

            // Fence content away from any front card that overlaps this card's vertical content band.
            var nearestFrontLeft = current.rect.maxX
            for upperIndex in (index + 1)..<placed.count {
                let upper = placed[upperIndex]
                let upperHasHalo = placed[0..<upperIndex].contains { lower in
                    rectsOverlap(upper.rect, lower.rect)
                }
                let upperHalo = upperHasHalo ? halo : 0
                let upperMinY = upper.rect.minY - upperHalo
                let upperMaxY = upper.rect.maxY + upperHalo
                let verticallyHitsContent =
                    upperMinY < current.contentRect.maxY - Self.epsilon
                    && current.contentRect.minY < upperMaxY - Self.epsilon
                if verticallyHitsContent, upper.rect.minX > current.rect.minX + Self.epsilon {
                    nearestFrontLeft = min(nearestFrontLeft, upper.rect.minX - upperHalo)
                }
            }

            let contentTrailingInset: CGFloat
            if nearestFrontLeft < current.rect.maxX - Self.epsilon {
                // Leave 4 pt breathing room inside the front card's halo while accounting for
                // ScheduleCard's built-in trailing horizontalPadding.
                let desiredTrailingFromCardEdge =
                    current.rect.maxX - (nearestFrontLeft - Self.contentFenceGap)
                contentTrailingInset = max(
                    0, desiredTrailingFromCardEdge - ScheduleCardStyle.horizontalPadding)
            } else {
                contentTrailingInset = 0
            }

            let availableContentWidth = max(current.rect.width - contentTrailingInset, 0)
            let presentation = resolveCardPresentation(
                item: current.item,
                cardHeight: current.rect.height,
                availableWidth: availableContentWidth,
                requiredCompactTime: current.usesCompactTime,
                requiredCompactStack: current.usesCompactStack
            )
            let resolvedBounds = contentMetrics.bounds(
                start: current.item.start,
                label: current.item.displayLabel,
                cardHeight: current.rect.height,
                usesCompactTime: presentation.usesCompactTime,
                usesCompactStack: presentation.usesCompactStack
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

            let info = TimelineItemLayoutInfo(
                id: current.item.id,
                item: current.item,
                rect: current.rect,
                zIndex: startingZIndex + index,
                isOverlappingFront: isOverlappingFront,
                contentTrailingInset: contentTrailingInset,
                usesCompactTime: presentation.usesCompactTime,
                usesCompactStack: presentation.usesCompactStack
            )
            return ValidatedLayoutEntry(
                layoutInfo: info,
                contentRect: validatedContentRect
            )
        }
    }

    private func resolveCardPresentation(
        item: TimelineItem,
        cardHeight: CGFloat,
        availableWidth: CGFloat,
        requiredCompactTime: Bool,
        requiredCompactStack: Bool
    ) -> (usesCompactTime: Bool, usesCompactStack: Bool) {
        let horizontalPaddingTotal = ScheduleCardStyle.horizontalPadding * 2

        if cardHeight >= ScheduleCardContentMetrics.stackedThresholdHeight {
            // Tall stacked cards keep AM/PM unless needed for text-aware overlap or ultra-narrow columns.
            let fullTimeWidth =
                contentMetrics.timeRowWidth(
                    start: item.start, usesCompactTime: false, usesCompactStack: false)
                + horizontalPaddingTotal
            let compactTime = requiredCompactTime || availableWidth < fullTimeWidth + 4
            return (compactTime, false)
        }

        if contentMetrics.canCompactStack(cardHeight: cardHeight) {
            // Medium cards (e.g. 30 min) stay 1-line horizontal when the full label fits,
            // and switch to a compact 2-line stack when narrow.
            let fullHorizontalWidth = contentMetrics.bounds(
                start: item.start,
                label: item.displayLabel,
                cardHeight: cardHeight,
                usesCompactTime: false,
                usesCompactStack: false
            ).width
            let compactStack = requiredCompactStack || fullHorizontalWidth > availableWidth
            guard compactStack else {
                return (requiredCompactTime, false)
            }
            let compactStackFullTimeWidth =
                contentMetrics.timeRowWidth(
                    start: item.start, usesCompactTime: false, usesCompactStack: true)
                + horizontalPaddingTotal
            let compactTime = requiredCompactTime || availableWidth < compactStackFullTimeWidth + 4
            return (compactTime, true)
        }

        // Short cards (15-20 min) stay 1-line horizontal; drop AM/PM when the name would clip.
        let fullHorizontalWidth = contentMetrics.bounds(
            start: item.start,
            label: item.displayLabel,
            cardHeight: cardHeight,
            usesCompactTime: false,
            usesCompactStack: false
        ).width
        let compactTime = requiredCompactTime || fullHorizontalWidth > availableWidth
        return (compactTime, false)
    }

    private func makePlacedItem(
        _ prepared: PreparedItem,
        span: HorizontalSpan,
        drawsHalo: Bool,
        usesCompactTime: Bool = false,
        usesCompactStack: Bool = false,
        contentBoundsOverride: ScheduleCardContentMetrics.Bounds? = nil
    ) -> PlacedItem {
        let rect = prepared.rect(in: span)
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
            drawsHalo: drawsHalo,
            usesCompactTime: usesCompactTime,
            usesCompactStack: usesCompactStack
        )
    }

    /// Split a time-overlapping group into sequential waves whose content bands do not collide.
    private func contentWaves(
        for items: [PreparedItem], halo: CGFloat
    ) -> [[PreparedItem]] {
        var waves: [[PreparedItem]] = []
        var currentWave: [PreparedItem] = []
        var currentMaxContentEnd: CGFloat?

        for item in items {
            let contentEnd = item.minY + item.contentBounds.height + halo
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
    private func contentColumnAssignments(
        for items: [PreparedItem], halo: CGFloat
    ) -> [Int] {
        var columnContentEnds: [CGFloat] = []
        return items.map { item in
            let contentEnd = item.minY + item.contentBounds.height + halo
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
        across slots: [HorizontalSpan],
        columnGap: CGFloat
    ) -> [Int]? {
        guard count > 0, !slots.isEmpty else { return nil }
        var counts = Array(repeating: 0, count: slots.count)
        for _ in 0..<count {
            var bestIndex: Int?
            var bestWidth: CGFloat = -1
            for index in slots.indices {
                let nextCount = counts[index] + 1
                let totalGap = columnGap * CGFloat(nextCount - 1)
                let width = (slots[index].width - totalGap) / CGFloat(nextCount)
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
        stripWidth: CGFloat,
        halo: CGFloat,
        candidateDrawsHalo: Bool
    ) -> [HorizontalSpan] {
        let candidateHalo = candidateDrawsHalo ? halo : 0
        var forbidden: [HorizontalSpan] = []

        for lower in placed {
            let overlapsVertically =
                lower.rect.minY < yMax - Self.epsilon
                && yMin < lower.rect.maxY - Self.epsilon
            if overlapsVertically {
                // Keep every overlapped lower card's continuous left strip uncovered.
                let stripEnd = min(lower.rect.minX + stripWidth, lower.rect.maxX)
                forbidden.append(
                    HorizontalSpan(
                        min: lower.rect.minX - candidateHalo,
                        max: stripEnd
                    )
                )
            }

            let overlapsContentVertically =
                lower.contentRect.minY < yMax + candidateHalo - Self.epsilon
                && yMin - candidateHalo < lower.contentRect.maxY - Self.epsilon
            if overlapsContentVertically {
                forbidden.append(
                    HorizontalSpan(
                        min: lower.contentRect.minX - candidateHalo,
                        max: lower.contentRect.maxX + candidateHalo
                    )
                )
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

    private func overlapsAny(rect: CGRect, placed: [PlacedItem]) -> Bool {
        placed.contains { rectsOverlap(rect, $0.rect) }
    }

    private func rectsOverlap(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let intersection = lhs.intersection(rhs)
        return !intersection.isNull
            && intersection.width > Self.epsilon
            && intersection.height > Self.epsilon
    }

    private var haloMargin: CGFloat {
        overlap.separation == .halo ? max(CGFloat(overlap.haloWidth), 0) : 0
    }

    private func effectiveStripWidth(in bounds: HorizontalSpan) -> CGFloat {
        min(max(CGFloat(overlap.stripWidth), 0), bounds.width)
    }

    private var cardWidth: CGFloat {
        Timeline.metrics.contentWidth(availableWidth: availableWidth)
    }

    private func cardWidth(columnCount: Int) -> CGFloat {
        guard columnCount > 1 else {
            return cardWidth
        }

        let spacing = Timeline.metrics.overlapColumnSpacing * CGFloat(columnCount - 1)
        return max((cardWidth - spacing) / CGFloat(columnCount), 0)
    }

    private func cardHeight(for item: TimelineItem) -> CGFloat {
        max(
            scale.height(
                from: item.start.timeOfDay,
                to: item.start.timeOfDay + item.durationMinutes
            )
                // 2x to account for top and bottom clearance both
                - Timeline.metrics.verticalCardMargin * 2,
            0
        )
    }

    private func cardX(column: Int, columnWidth: CGFloat) -> CGFloat {
        Timeline.metrics.contentLeadingInset
            + CGFloat(column) * (columnWidth + Timeline.metrics.overlapColumnSpacing)
    }

    private func cardY(for item: TimelineItem) -> CGFloat {
        return scale.yOffset(for: item.start.timeOfDay)
            + Timeline.metrics.verticalCardMargin
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

/// Exact 2D geometric verifier enforcing content visibility and continuous time-edge visibility.
nonisolated enum TimelineLayoutValidator {
    enum Violation: Equatable, CustomStringConvertible, Sendable {
        case outOfBounds(TimelineItem.ID)
        case nonPositiveWidth(TimelineItem.ID)
        case contentObscured(covered: TimelineItem.ID, by: TimelineItem.ID)
        case timeEdgeObscured(covered: TimelineItem.ID, by: TimelineItem.ID)
        case contentFencedOut(TimelineItem.ID)

        var description: String {
            switch self {
            case .outOfBounds(let id):
                "Card \(id.sortKey) extends outside timeline bounds"
            case .nonPositiveWidth(let id):
                "Card \(id.sortKey) has non-positive width"
            case .contentObscured(let covered, let by):
                "Card \(covered.sortKey) content is obscured by \(by.sortKey)"
            case .timeEdgeObscured(let covered, let by):
                "Card \(covered.sortKey) continuous time-edge strip is obscured by \(by.sortKey)"
            case .contentFencedOut(let id):
                "Card \(id.sortKey) has no remaining content width after trailing inset"
            }
        }
    }

    private static let epsilon: CGFloat = 0.01

    static func validate(
        entries: [ValidatedLayoutEntry],
        bounds: HorizontalSpan,
        overlap: ScheduleCardTuning.Overlap
    ) -> [Violation] {
        let halo = overlap.separation == .halo ? max(CGFloat(overlap.haloWidth), 0) : 0
        let stripWidth = max(CGFloat(overlap.stripWidth), 0)
        let sorted = entries.sorted { $0.layoutInfo.zIndex < $1.layoutInfo.zIndex }
        var violations: [Violation] = []

        for index in sorted.indices {
            let lower = sorted[index]
            let lowerRect = lower.layoutInfo.rect

            if lowerRect.width <= epsilon {
                violations.append(.nonPositiveWidth(lower.layoutInfo.id))
                continue
            }
            if lowerRect.minX < bounds.min - epsilon || lowerRect.maxX > bounds.max + epsilon {
                violations.append(.outOfBounds(lower.layoutInfo.id))
            }
            if lowerRect.width - lower.layoutInfo.contentTrailingInset <= epsilon {
                violations.append(.contentFencedOut(lower.layoutInfo.id))
            }

            let requiredStrip = min(stripWidth, lowerRect.width)
            let leftStrip = CGRect(
                x: lowerRect.minX,
                y: lowerRect.minY,
                width: requiredStrip,
                height: lowerRect.height
            )

            for upperIndex in (index + 1)..<sorted.count {
                let upper = sorted[upperIndex]
                guard upper.layoutInfo.zIndex > lower.layoutInfo.zIndex else { continue }

                let upperRect = upper.layoutInfo.rect
                let upperHalo = upper.layoutInfo.isOverlappingFront ? halo : 0
                let upperOcclusionRect = upperRect.insetBy(dx: -upperHalo, dy: -upperHalo)

                if intersects(lower.contentRect, upperOcclusionRect) {
                    violations.append(
                        .contentObscured(
                            covered: lower.layoutInfo.id,
                            by: upper.layoutInfo.id
                        )
                    )
                }

                if intersects(leftStrip, upperRect) {
                    violations.append(
                        .timeEdgeObscured(
                            covered: lower.layoutInfo.id,
                            by: upper.layoutInfo.id
                        )
                    )
                }
            }
        }

        return violations
    }

    private static func intersects(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = lhs.intersection(rhs)
        return !overlap.isNull && overlap.width > epsilon && overlap.height > epsilon
    }
}

nonisolated struct HorizontalSpan: Equatable, Sendable {
    let min: CGFloat
    let max: CGFloat

    var width: CGFloat { Swift.max(max - min, 0) }
}

struct ValidatedLayoutEntry {
    let layoutInfo: TimelineItemLayoutInfo
    let contentRect: CGRect
}

struct TimelineItemLayoutInfo: Identifiable {
    let id: TimelineItem.ID
    let item: TimelineItem
    let rect: CGRect
    let zIndex: Int
    let isOverlappingFront: Bool
    let contentTrailingInset: CGFloat
    let usesCompactTime: Bool
    let usesCompactStack: Bool

    init(
        id: TimelineItem.ID,
        item: TimelineItem,
        rect: CGRect,
        zIndex: Int = 0,
        isOverlappingFront: Bool = false,
        contentTrailingInset: CGFloat = 0,
        usesCompactTime: Bool = false,
        usesCompactStack: Bool = false
    ) {
        self.id = id
        self.item = item
        self.rect = rect
        self.zIndex = zIndex
        self.isOverlappingFront = isOverlappingFront
        self.contentTrailingInset = contentTrailingInset
        self.usesCompactTime = usesCompactTime
        self.usesCompactStack = usesCompactStack
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
    let drawsHalo: Bool
    let usesCompactTime: Bool
    let usesCompactStack: Bool
}

private struct TimelineItemColumnAssignment {
    let item: TimelineItem
    let column: Int
}

extension Minutes {
    var px: CGFloat {
        CGFloat(self) * Timeline.metrics.pixelsPerMinute
    }
}

extension ClosedRange where Bound == TimeOfDay {
    var px: CGFloat { self.minutes.px }
}

extension Range where Bound == TimeOfDay {
    var px: CGFloat { self.minutes.px }
}
