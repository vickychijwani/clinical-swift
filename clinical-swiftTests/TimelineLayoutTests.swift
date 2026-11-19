import ClinicalModels
import CoreGraphics
import Foundation
import Testing

@testable import clinical_swift

struct TimelineLayoutTests {
    private let availableWidth: CGFloat = 300

    @Test func appointmentsTouchingAtBoundaryUseFullWidth() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let layouts = legacyEngine.layout(items: [
            appointment(id: firstID, startHour: 9, startMinute: 0, duration: 30),
            appointment(id: secondID, startHour: 9, startMinute: 30, duration: 30),
        ])

        let first = try layout(for: firstID, in: layouts)
        let second = try layout(for: secondID, in: layouts)

        #expect(first.rect.minX == Timeline.metrics.contentLeadingInset)
        #expect(second.rect.minX == Timeline.metrics.contentLeadingInset)
        #expect(first.rect.width == contentWidth)
        #expect(second.rect.width == contentWidth)
    }

    @Test func twoAppointmentsWithSameStartSplitIntoTwoColumnsInCurrentMode() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let layouts = legacyEngine.layout(items: [
            appointment(id: firstID, startHour: 9, startMinute: 0, duration: 30),
            appointment(id: secondID, startHour: 9, startMinute: 0, duration: 30),
        ])

        let first = try layout(for: firstID, in: layouts)
        let second = try layout(for: secondID, in: layouts)
        let columnWidth = (contentWidth - Timeline.metrics.overlapColumnSpacing) / 2

        #expect(first.rect.minX == Timeline.metrics.contentLeadingInset)
        #expect(
            second.rect.minX == Timeline.metrics.contentLeadingInset + columnWidth
                + Timeline.metrics.overlapColumnSpacing)
        #expect(first.rect.width == columnWidth)
        #expect(second.rect.width == columnWidth)
    }

    @Test func threeSimultaneousAppointmentsSplitIntoThreeColumnsInCurrentMode() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let thirdID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let layouts = legacyEngine.layout(items: [
            appointment(id: firstID, startHour: 9, startMinute: 0, duration: 30),
            appointment(id: secondID, startHour: 9, startMinute: 0, duration: 30),
            appointment(id: thirdID, startHour: 9, startMinute: 0, duration: 30),
        ])

        let first = try layout(for: firstID, in: layouts)
        let second = try layout(for: secondID, in: layouts)
        let third = try layout(for: thirdID, in: layouts)
        let columnWidth = (contentWidth - Timeline.metrics.overlapColumnSpacing * 2) / 3

        #expect(first.rect.minX == Timeline.metrics.contentLeadingInset)
        #expect(
            second.rect.minX == Timeline.metrics.contentLeadingInset + columnWidth
                + Timeline.metrics.overlapColumnSpacing)
        #expect(
            third.rect.minX == Timeline.metrics.contentLeadingInset
                + (columnWidth + Timeline.metrics.overlapColumnSpacing) * 2)
        #expect(first.rect.width == columnWidth)
        #expect(second.rect.width == columnWidth)
        #expect(third.rect.width == columnWidth)
    }

    @Test func staggeredOverlapReusesEndedColumnsWithinSameGroupInCurrentMode() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let thirdID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let layouts = legacyEngine.layout(items: [
            appointment(id: firstID, startHour: 9, startMinute: 0, duration: 30),
            appointment(id: secondID, startHour: 9, startMinute: 15, duration: 30),
            appointment(id: thirdID, startHour: 9, startMinute: 30, duration: 30),
        ])

        let first = try layout(for: firstID, in: layouts)
        let second = try layout(for: secondID, in: layouts)
        let third = try layout(for: thirdID, in: layouts)
        let columnWidth = (contentWidth - Timeline.metrics.overlapColumnSpacing) / 2

        #expect(first.rect.minX == Timeline.metrics.contentLeadingInset)
        #expect(
            second.rect.minX == Timeline.metrics.contentLeadingInset + columnWidth
                + Timeline.metrics.overlapColumnSpacing)
        #expect(third.rect.minX == first.rect.minX)
        #expect(first.rect.width == columnWidth)
        #expect(second.rect.width == columnWidth)
        #expect(third.rect.width == columnWidth)
    }

    @Test func sameEndOverlapLeavesContinuousEdgeStripVisible() throws {
        let longID = UUID()
        let shortID = UUID()
        let items = [
            appointment(
                id: longID, name: "Anjali Subramanian", startHour: 10, startMinute: 0, duration: 120
            ),
            appointment(
                id: shortID, name: "Kabir Malhotra", startHour: 11, startMinute: 45, duration: 15),
        ]

        for mode in [ScheduleCardTuning.Overlap.Mode.cascade, .textAware] {
            let overlap = ScheduleCardTuning.Overlap(mode: mode, separation: .halo, stripWidth: 18)
            let layouts = TimelineLayoutEngine(
                availableWidth: 380, scale: TimelineScale(items: items), overlap: overlap
            ).layout(items: items)

            let longCard = try layout(for: longID, in: layouts)
            let shortCard = try layout(for: shortID, in: layouts)
            let fullWidth = Timeline.metrics.contentWidth(availableWidth: 380)

            #expect(longCard.rect.minX == Timeline.metrics.contentLeadingInset)
            #expect(longCard.rect.width == fullWidth)
            #expect(shortCard.rect.minX == longCard.rect.minX + 18)
            #expect(shortCard.rect.width == fullWidth - 18)
            #expect(shortCard.zIndex > longCard.zIndex)
            #expect(shortCard.isOverlappingFront)
            #expect(!longCard.isOverlappingFront)
            #expect(longCard.contentTrailingInset == 0)
        }
    }

    @Test func threeCardCascadeStepsCleanlyAndPreservesStrips() throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let items = [
            unavailable(id: firstID, label: "Travel", startHour: 9, startMinute: 0, duration: 180),
            appointment(
                id: secondID, name: "Anjali Desai", startHour: 10, startMinute: 0, duration: 90),
            appointment(
                id: thirdID, name: "Priya Narayanan", startHour: 10, startMinute: 45, duration: 45),
        ]

        let overlap = ScheduleCardTuning.Overlap(mode: .cascade, separation: .halo, stripWidth: 18)
        let layouts = TimelineLayoutEngine(
            availableWidth: 380, scale: TimelineScale(items: items), overlap: overlap
        ).layout(items: items)

        let first = try #require(layouts.first { $0.id == .unavailableTime(firstID) })
        let second = try layout(for: secondID, in: layouts)
        let third = try layout(for: thirdID, in: layouts)
        let leading = Timeline.metrics.contentLeadingInset
        let fullWidth = Timeline.metrics.contentWidth(availableWidth: 380)

        #expect(first.rect.minX == leading)
        #expect(first.rect.width == fullWidth)
        #expect(second.rect.minX == leading + 18)
        #expect(second.rect.width == fullWidth - 18)
        #expect(third.rect.minX == leading + 36)
        #expect(third.rect.width == fullWidth - 36)
        #expect(first.zIndex < second.zIndex)
        #expect(second.zIndex < third.zIndex)
    }

    @Test func textAwareOverlapsPastShortNameWhileCascadeSplitsEqually() throws {
        let backID = UUID()
        let frontID = UUID()
        let items = [
            appointment(id: backID, name: "Ana", startHour: 9, startMinute: 0, duration: 120),
            appointment(
                id: frontID, name: "Priya Narayanan", startHour: 9, startMinute: 15, duration: 45),
        ]
        let width: CGFloat = 402
        let fullWidth = Timeline.metrics.contentWidth(availableWidth: width)

        let cascadeLayouts = TimelineLayoutEngine(
            availableWidth: width,
            scale: TimelineScale(items: items),
            overlap: .init(mode: .cascade)
        ).layout(items: items)
        let cascadeBack = try layout(for: backID, in: cascadeLayouts)
        let cascadeFront = try layout(for: frontID, in: cascadeLayouts)
        #expect(abs(cascadeBack.rect.width - fullWidth / 2) < 0.01)
        #expect(abs(cascadeFront.rect.width - fullWidth / 2) < 0.01)
        #expect(!cascadeFront.isOverlappingFront)

        let textAwareLayouts = TimelineLayoutEngine(
            availableWidth: width,
            scale: TimelineScale(items: items),
            overlap: .init(mode: .textAware, separation: .halo, stripWidth: 18, haloWidth: 2)
        ).layout(items: items)
        let textBack = try layout(for: backID, in: textAwareLayouts)
        let textFront = try layout(for: frontID, in: textAwareLayouts)

        #expect(textBack.rect.width == fullWidth)
        #expect(textFront.rect.width > fullWidth * 0.6)
        #expect(textFront.isOverlappingFront)
        #expect(textBack.contentTrailingInset > 0)
        // Content fence must stop strictly before the front card's halo.
        let fencedContentMaxX =
            textBack.rect.maxX - ScheduleCardStyle.horizontalPadding - textBack.contentTrailingInset
        #expect(fencedContentMaxX < textFront.rect.minX - 2)
    }

    @Test func textAwareFallsBackToFairSplitWhenBackNameIsLong() throws {
        let backID = UUID()
        let frontID = UUID()
        let items = [
            appointment(
                id: backID, name: "Dr. Meera Venkatasubramanian", startHour: 9, startMinute: 0,
                duration: 120),
            appointment(
                id: frontID, name: "Priya Narayanan", startHour: 9, startMinute: 15, duration: 45),
        ]
        let width: CGFloat = 340
        let fullWidth = Timeline.metrics.contentWidth(availableWidth: width)

        let layouts = TimelineLayoutEngine(
            availableWidth: width,
            scale: TimelineScale(items: items),
            overlap: .init(mode: .textAware)
        ).layout(items: items)

        let back = try layout(for: backID, in: layouts)
        let front = try layout(for: frontID, in: layouts)
        #expect(abs(back.rect.width - fullWidth / 2) < 0.01)
        #expect(abs(front.rect.width - fullWidth / 2) < 0.01)
    }

    @Test func twoSimultaneousAppointmentsInsideLongBlockShareCascadedWidth() throws {
        let blockID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let items = [
            unavailable(id: blockID, label: "Travel", startHour: 9, startMinute: 0, duration: 240),
            appointment(
                id: firstID, name: "Anjali Subramanian", startHour: 10, startMinute: 0, duration: 60
            ),
            appointment(
                id: secondID, name: "Priya Narayanan", startHour: 10, startMinute: 0, duration: 60),
        ]
        let width: CGFloat = 380
        let fullWidth = Timeline.metrics.contentWidth(availableWidth: width)
        let overlap = ScheduleCardTuning.Overlap(
            mode: .cascade, separation: .halo, stripWidth: 18, haloWidth: 2)

        let layouts = TimelineLayoutEngine(
            availableWidth: width, scale: TimelineScale(items: items), overlap: overlap
        ).layout(items: items)

        let block = try #require(layouts.first { $0.id == .unavailableTime(blockID) })
        let first = try layout(for: firstID, in: layouts)
        let second = try layout(for: secondID, in: layouts)

        #expect(block.rect.width == fullWidth)
        #expect(first.rect.minX == block.rect.minX + 18)
        // Halo gap separates side-by-side front cards over a shared background card.
        #expect(abs((second.rect.minX - first.rect.maxX) - 2) < 0.01)
        #expect(abs(second.rect.maxX - block.rect.maxX) < 0.01)
        #expect(first.isOverlappingFront)
        #expect(second.isOverlappingFront)
    }

    @Test func laterCardOverTwoActiveColumnsPreservesBothLeftStrips() throws {
        let leftID = UUID()
        let rightID = UUID()
        let laterID = UUID()
        let items = [
            appointment(
                id: leftID, name: "Anjali Subramanian", startHour: 9, startMinute: 0, duration: 180),
            appointment(
                id: rightID, name: "Kabir Malhotra", startHour: 9, startMinute: 0, duration: 120),
            appointment(
                id: laterID, name: "Priya Narayanan", startHour: 10, startMinute: 0, duration: 30),
        ]
        let overlap = ScheduleCardTuning.Overlap(
            mode: .cascade, separation: .halo, stripWidth: 18, haloWidth: 2)

        let layouts = TimelineLayoutEngine(
            availableWidth: 402, scale: TimelineScale(items: items), overlap: overlap
        ).layout(items: items)

        let left = try layout(for: leftID, in: layouts)
        let right = try layout(for: rightID, in: layouts)
        let later = try layout(for: laterID, in: layouts)

        let leftStrip = CGRect(
            x: left.rect.minX, y: left.rect.minY, width: 18, height: left.rect.height)
        let rightStrip = CGRect(
            x: right.rect.minX, y: right.rect.minY, width: 18, height: right.rect.height)

        #expect(leftStrip.intersection(later.rect).isEmpty)
        #expect(rightStrip.intersection(later.rect).isEmpty)
        #expect(later.rect.width > 120)
    }

    @Test func validatorRejectsObscuredContentAndObscuredEndEdge() {
        let backID = TimelineItem.ID.appointment(UUID())
        let frontID = TimelineItem.ID.appointment(UUID())
        let backItem = appointment(
            id: UUID(), name: "Back", startHour: 10, startMinute: 0, duration: 120)
        let frontItem = appointment(
            id: UUID(), name: "Front", startHour: 11, startMinute: 45, duration: 15)
        let bounds = HorizontalSpan(min: 56, max: 356)
        let overlap = ScheduleCardTuning.Overlap(
            mode: .cascade, separation: .halo, stripWidth: 18, haloWidth: 2)

        // Full-width 15m card at 11:45–12:00 covers the 2h card's 12:00 end edge.
        let badEdgeEntries = [
            ValidatedLayoutEntry(
                layoutInfo: TimelineItemLayoutInfo(
                    id: backID, item: backItem,
                    rect: CGRect(x: 56, y: 60, width: 300, height: 120),
                    zIndex: 0),
                contentRect: CGRect(x: 56, y: 60, width: 300, height: 43)
            ),
            ValidatedLayoutEntry(
                layoutInfo: TimelineItemLayoutInfo(
                    id: frontID, item: frontItem,
                    rect: CGRect(x: 56, y: 165, width: 300, height: 15),
                    zIndex: 1, isOverlappingFront: true),
                contentRect: CGRect(x: 56, y: 165, width: 300, height: 15)
            ),
        ]
        let edgeViolations = TimelineLayoutValidator.validate(
            entries: badEdgeEntries, bounds: bounds, overlap: overlap)
        #expect(edgeViolations.contains(.timeEdgeObscured(covered: backID, by: frontID)))

        // Indented card placed over the back card's text band obscures its content.
        let badContentEntries = [
            ValidatedLayoutEntry(
                layoutInfo: TimelineItemLayoutInfo(
                    id: backID, item: backItem,
                    rect: CGRect(x: 56, y: 60, width: 300, height: 120),
                    zIndex: 0),
                contentRect: CGRect(x: 56, y: 60, width: 300, height: 43)
            ),
            ValidatedLayoutEntry(
                layoutInfo: TimelineItemLayoutInfo(
                    id: frontID, item: frontItem,
                    rect: CGRect(x: 74, y: 75, width: 282, height: 30),
                    zIndex: 1, isOverlappingFront: true),
                contentRect: CGRect(x: 74, y: 75, width: 282, height: 30)
            ),
        ]
        let contentViolations = TimelineLayoutValidator.validate(
            entries: badContentEntries, bounds: bounds, overlap: overlap)
        #expect(contentViolations.contains(.contentObscured(covered: backID, by: frontID)))
    }

    @Test func compactTimeAndCompactStackUnlockOverlapInThreeCardSimultaneousGroup() throws {
        let anaID = UUID()
        let rajID = UUID()
        let meeraID = UUID()
        let items = [
            appointment(id: anaID, name: "Ana", startHour: 12, startMinute: 15, duration: 45),
            appointment(id: rajID, name: "Raj", startHour: 12, startMinute: 15, duration: 45),
            appointment(
                id: meeraID, name: "Meera Subramanian", startHour: 12, startMinute: 15, duration: 30
            ),
        ]
        // At 340 pt (276 pt content width, 92 pt fair share), full "12:15 PM" misses overlap by 2 pt;
        // compact "12:15" unlocks overlap so Meera gets substantially more than 1/3 width.
        let layouts = TimelineLayoutEngine(
            availableWidth: 340,
            scale: TimelineScale(items: items),
            overlap: .init(mode: .textAware, separation: .halo, stripWidth: 18, haloWidth: 2)
        ).layout(items: items)

        let ana = try layout(for: anaID, in: layouts)
        let raj = try layout(for: rajID, in: layouts)
        let meera = try layout(for: meeraID, in: layouts)

        #expect(ana.usesCompactTime)
        #expect(raj.usesCompactTime)
        #expect(meera.rect.width > 120)
        #expect(meera.usesCompactStack)
        #expect(meera.isOverlappingFront)
    }

    @Test func fullWidthThirtyMinCardKeepsSingleLineAndFullTimeWhileNarrowShortCardDropsAMPM()
        throws
    {
        let fullID = UUID()
        let fullItems = [
            appointment(
                id: fullID, name: "Arjun Sethi", startHour: 12, startMinute: 30, duration: 30)
        ]
        let fullLayouts = TimelineLayoutEngine(
            availableWidth: 402, scale: TimelineScale(items: fullItems)
        ).layout(items: fullItems)
        let full = try layout(for: fullID, in: fullLayouts)
        #expect(!full.usesCompactTime)
        #expect(!full.usesCompactStack)

        // Two simultaneous 15-min cards with long names stay horizontal and drop AM/PM to keep names readable.
        let leftID = UUID()
        let rightID = UUID()
        let narrowItems = [
            appointment(
                id: leftID, name: "Anjali Subramanian", startHour: 10, startMinute: 0, duration: 15),
            appointment(
                id: rightID, name: "Priya Narayanan", startHour: 10, startMinute: 0, duration: 15),
        ]
        let narrowLayouts = TimelineLayoutEngine(
            availableWidth: 340,
            scale: TimelineScale(items: narrowItems),
            overlap: .init(mode: .textAware)
        ).layout(items: narrowItems)
        let left = try layout(for: leftID, in: narrowLayouts)
        let right = try layout(for: rightID, in: narrowLayouts)
        #expect(left.usesCompactTime)
        #expect(!left.usesCompactStack)
        #expect(right.usesCompactTime)
        #expect(!right.usesCompactStack)
    }

    @Test func randomizedSchedulesNeverViolateOverlapInvariants() {
        var rng = SeededGenerator(seed: 0xB17E_AA05)
        let names = [
            "Ana",
            "Raj",
            "Anjali Desai",
            "Priya Narayanan",
            "Kabir Malhotra",
            "Dr. Meera Venkatasubramanian",
        ]
        let durations = [15, 20, 30, 45, 60, 90, 120, 180]
        let widths: [CGFloat] = [280, 340, 402]
        let modes: [ScheduleCardTuning.Overlap.Mode] = [.cascade, .textAware]
        let separations: [ScheduleCardTuning.Overlap.Separation] = [.halo, .shadow, .flat]
        let metrics = ScheduleCardContentMetrics()

        for trial in 0..<300 {
            let count = Int(rng.next() % 7) + 2
            let baseHour = (trial % 4 == 0) ? 12 : 9
            var items: [TimelineItem] = []
            for _ in 0..<count {
                let offsetMinutes = Int(rng.next() % 24) * 5
                let totalStart = baseHour * 60 + offsetMinutes
                let hour = min(totalStart / 60, 19)
                let minute = totalStart % 60
                let duration = durations[Int(rng.next() % UInt64(durations.count))]
                let name = names[Int(rng.next() % UInt64(names.count))]
                if rng.next() % 4 == 0 {
                    items.append(
                        unavailable(
                            id: UUID(), label: name, startHour: hour, startMinute: minute,
                            duration: duration))
                } else {
                    items.append(
                        appointment(
                            id: UUID(), name: name, startHour: hour, startMinute: minute,
                            duration: duration))
                }
            }

            let width = widths[trial % widths.count]
            let mode = modes[trial % modes.count]
            let separation = separations[trial % separations.count]
            let overlap = ScheduleCardTuning.Overlap(
                mode: mode, separation: separation, stripWidth: 18, haloWidth: 2)
            let scale = TimelineScale(items: items)
            let engine = TimelineLayoutEngine(
                availableWidth: width, scale: scale, overlap: overlap, contentMetrics: metrics)
            let layouts = engine.layout(items: items)
            #expect(layouts.count == items.count)

            let bounds = HorizontalSpan(
                min: Timeline.metrics.contentLeadingInset,
                max: Timeline.metrics.contentLeadingInset
                    + Timeline.metrics.contentWidth(availableWidth: width)
            )
            let entries = layouts.map { info -> ValidatedLayoutEntry in
                let measured = metrics.bounds(
                    start: info.item.start,
                    label: info.item.displayLabel,
                    cardHeight: info.rect.height,
                    usesCompactTime: info.usesCompactTime,
                    usesCompactStack: info.usesCompactStack
                )
                let protectedWidth =
                    mode == .textAware ? min(info.rect.width, measured.width) : info.rect.width
                let contentRect = CGRect(
                    x: info.rect.minX,
                    y: info.rect.minY,
                    width: protectedWidth,
                    height: min(info.rect.height, measured.height)
                )
                return ValidatedLayoutEntry(layoutInfo: info, contentRect: contentRect)
            }
            let violations = TimelineLayoutValidator.validate(
                entries: entries, bounds: bounds, overlap: overlap)
            #expect(
                violations.isEmpty,
                "Trial \(trial) (\(mode.rawValue)/\(separation.rawValue)) violated: \(violations)")
        }
    }

    @Test func verticalPositionAndHeightUseExistingMinuteMath() throws {
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let layouts = legacyEngine.layout(items: [
            appointment(id: id, startHour: 9, startMinute: 30, duration: 45)
        ])

        let layout = try layout(for: id, in: layouts)

        #expect(layout.rect.minY == 30)
        #expect(layout.rect.height == 45)
    }

    @Test func timelineScaleMapsTimeBeforeBreakWithinFirstSegment() {
        #expect(scale.yOffset(for: TimeOfDay(10, 30)) == 90)
    }

    @Test func compactTimelineScaleProportionallyMapsTimeDuringBreak() {
        #expect(scale.yOffset(for: TimeOfDay(14, 30)) == 256)
    }

    @Test func timelineScaleIncludesBreakHeightAfterBreak() {
        #expect(scale.yOffset(for: TimeOfDay(17, 30)) == 362)
    }

    @Test func compactAndExpandedScalesHaveExpectedTotalHeight() {
        let breakAppointment = appointment(
            id: UUID(),
            startHour: 14,
            startMinute: 0,
            duration: 30
        )
        let expandedScale = TimelineScale(items: [breakAppointment])

        #expect(scale.totalHeight == 572)
        #expect(expandedScale.totalHeight == 720)
        #expect(expandedScale.yOffset(for: TimeOfDay(14, 30)) == 330)
        #expect(expandedScale.yOffset(for: TimeOfDay(17, 30)) == 510)
    }

    @Test func appointmentStartWithinHalfOpenBreakRangeExpandsScale() {
        let atBreakStart = appointment(
            id: UUID(),
            startHour: 13,
            startMinute: 0,
            duration: 30,
            status: .draft
        )
        let duringBreak = appointment(
            id: UUID(),
            startHour: 14,
            startMinute: 30,
            duration: 30
        )
        let beforeBreak = appointment(
            id: UUID(),
            startHour: 12,
            startMinute: 30,
            duration: 60
        )
        let atBreakEnd = appointment(
            id: UUID(),
            startHour: 16,
            startMinute: 0,
            duration: 30
        )

        #expect(TimelineScale(items: [atBreakStart]).isBreakExpanded)
        #expect(TimelineScale(items: [duringBreak]).isBreakExpanded)
        #expect(!TimelineScale(items: [beforeBreak]).isBreakExpanded)
        #expect(!TimelineScale(items: [atBreakEnd]).isBreakExpanded)
    }

    @Test func compactScaleCompressesAppointmentCrossingIntoBreak() throws {
        let id = UUID()
        let crossingAppointment = appointment(
            id: id,
            startHour: 12,
            startMinute: 30,
            duration: 60
        )
        let items = [crossingAppointment]
        let layouts = legacyEngine(for: items).layout(items: items)
        let layout = try layout(for: id, in: layouts)

        #expect(layout.rect.minY == 210)
        #expect(abs(layout.rect.height - 35.333_333) < 0.001)
    }

    @Test func expandedScalePlacesAppointmentWithinBreakAtFullScale() throws {
        let id = UUID()
        let breakAppointment = appointment(
            id: id,
            startHour: 14,
            startMinute: 0,
            duration: 45,
            status: .draft
        )
        let items = [breakAppointment]
        let layouts = legacyEngine(for: items).layout(items: items)
        let layout = try layout(for: id, in: layouts)

        #expect(layout.rect.minY == 300)
        #expect(layout.rect.height == 45)
    }

    @Test func overlappingAppointmentsWithinBreakUseColumnsInCurrentMode() throws {
        let firstID = UUID()
        let secondID = UUID()
        let items = [
            appointment(id: firstID, startHour: 14, startMinute: 0, duration: 30),
            appointment(id: secondID, startHour: 14, startMinute: 0, duration: 30),
        ]
        let layouts = legacyEngine(for: items).layout(items: items)

        #expect(try layout(for: firstID, in: layouts).rect.width == contentWidth / 2)
        #expect(try layout(for: secondID, in: layouts).rect.width == contentWidth / 2)
    }

    @Test func hourMarkersFollowBreakPresentation() {
        let breakAppointment = appointment(
            id: UUID(),
            startHour: 14,
            startMinute: 0,
            duration: 30
        )
        let expandedScale = TimelineScale(items: [breakAppointment])

        #expect(scale.hourMarkers.map(\.hour) == [9, 10, 11, 12, 13, 16, 17, 18, 19, 20, 21])
        #expect(expandedScale.hourMarkers.map(\.hour) == Array(9...21))
    }

    @Test func nowTimeWithinBreakIsVisibleOnlyWhenExpanded() {
        let breakAppointment = appointment(
            id: UUID(),
            startHour: 14,
            startMinute: 0,
            duration: 30
        )
        let expandedScale = TimelineScale(items: [breakAppointment])

        #expect(!scale.showsTime(TimeOfDay(14, 30)))
        #expect(expandedScale.showsTime(TimeOfDay(14, 30)))
    }

    private var legacyEngine: TimelineLayoutEngine {
        TimelineLayoutEngine(
            availableWidth: availableWidth,
            scale: scale,
            overlap: .init(mode: .current)
        )
    }

    private func legacyEngine(for items: [TimelineItem]) -> TimelineLayoutEngine {
        TimelineLayoutEngine(
            availableWidth: availableWidth,
            scale: TimelineScale(items: items),
            overlap: .init(mode: .current)
        )
    }

    private var contentWidth: CGFloat {
        Timeline.metrics.contentWidth(availableWidth: availableWidth)
    }

    private var scale: TimelineScale {
        TimelineScale(items: [])
    }

    private func appointment(
        id: UUID,
        name: String = "Patient",
        startHour: Int,
        startMinute: Int,
        duration: Int,
        status: Appointment.Status = .scheduled
    ) -> TimelineItem {
        .appointment(
            Appointment(
                id: id,
                patientName: name,
                start: Date(timeIntervalSinceReferenceDate: 804_600_000)
                    .setTime(startHour, startMinute),
                durationMinutes: duration,
                status: status
            )
        )
    }

    private func unavailable(
        id: UUID,
        label: String? = "Blocked",
        startHour: Int,
        startMinute: Int,
        duration: Int
    ) -> TimelineItem {
        .unavailableTime(
            UnavailableTime(
                id: id,
                label: label,
                start: Date(timeIntervalSinceReferenceDate: 804_600_000)
                    .setTime(startHour, startMinute),
                durationMinutes: duration
            )
        )
    }

    private func layout(
        for id: UUID,
        in layouts: [TimelineItemLayoutInfo]
    ) throws -> TimelineItemLayoutInfo {
        try #require(layouts.first { $0.id == .appointment(id) })
    }
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 16
    }
}
