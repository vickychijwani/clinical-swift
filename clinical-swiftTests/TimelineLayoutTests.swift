import CoreGraphics
import Foundation
import Testing

@testable import clinical_swift

struct TimelineLayoutTests {
    private let availableWidth: CGFloat = 300

    @Test func nonOverlappingAppointmentsUseFullWidth() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let layouts = engine.layout(items: [
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

    @Test func twoAppointmentsWithSameStartSplitIntoTwoColumns() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let layouts = engine.layout(items: [
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

    @Test func threeSimultaneousAppointmentsSplitIntoThreeColumns() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let thirdID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let layouts = engine.layout(items: [
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

    @Test func staggeredOverlapReusesEndedColumnsWithinSameGroup() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let thirdID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let layouts = engine.layout(items: [
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

    @Test func appointmentsTouchingAtBoundaryDoNotSplitWidth() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let layouts = engine.layout(items: [
            appointment(id: firstID, startHour: 9, startMinute: 0, duration: 30),
            appointment(id: secondID, startHour: 9, startMinute: 30, duration: 30),
        ])

        let first = try layout(for: firstID, in: layouts)
        let second = try layout(for: secondID, in: layouts)

        #expect(first.rect.width == contentWidth)
        #expect(second.rect.width == contentWidth)
    }

    @Test func verticalPositionAndHeightUseExistingMinuteMath() throws {
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let layouts = engine.layout(items: [
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
        let layouts = engine(for: items).layout(items: items)
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
        let layouts = engine(for: items).layout(items: items)
        let layout = try layout(for: id, in: layouts)

        #expect(layout.rect.minY == 300)
        #expect(layout.rect.height == 45)
    }

    @Test func overlappingAppointmentsWithinBreakUseColumns() throws {
        let firstID = UUID()
        let secondID = UUID()
        let items = [
            appointment(id: firstID, startHour: 14, startMinute: 0, duration: 30),
            appointment(id: secondID, startHour: 14, startMinute: 0, duration: 30),
        ]
        let layouts = engine(for: items).layout(items: items)

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

    private var engine: TimelineLayoutEngine {
        TimelineLayoutEngine(
            availableWidth: availableWidth,
            scale: scale
        )
    }

    private func engine(for items: [TimelineItem]) -> TimelineLayoutEngine {
        TimelineLayoutEngine(
            availableWidth: availableWidth,
            scale: TimelineScale(items: items)
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
        startHour: Int,
        startMinute: Int,
        duration: Int,
        status: Appointment.Status = .scheduled
    ) -> TimelineItem {
        .appointment(
            Appointment(
                id: id,
                patientName: "Patient",
                start: Date(timeIntervalSinceReferenceDate: 804_600_000)
                    .setTime(startHour, startMinute),
                durationMinutes: duration,
                status: status
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
