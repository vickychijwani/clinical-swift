import CoreGraphics
import Foundation
import Testing

@testable import clinical_swift

struct TimelineLayoutTests {
    private let metrics = TimelineMetrics(
        hourHeight: 60,
        timeColumnWidth: 40,
        verticalPadding: 8,
        horizontalCardMargin: 12,
        verticalCardMargin: 1,
        overlapColumnSpacing: 2
    )
    private let availableWidth: CGFloat = 300

    @Test func nonOverlappingAppointmentsUseFullWidth() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let layouts = engine.layout(appointments: [
            appointment(id: firstID, startHour: 9, startMinute: 0, duration: 30),
            appointment(id: secondID, startHour: 9, startMinute: 30, duration: 30),
        ])

        let first = try layout(for: firstID, in: layouts)
        let second = try layout(for: secondID, in: layouts)

        #expect(first.rect.minX == metrics.contentLeadingInset)
        #expect(second.rect.minX == metrics.contentLeadingInset)
        #expect(first.rect.width == contentWidth)
        #expect(second.rect.width == contentWidth)
    }

    @Test func twoAppointmentsWithSameStartSplitIntoTwoColumns() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let layouts = engine.layout(appointments: [
            appointment(id: firstID, startHour: 9, startMinute: 0, duration: 30),
            appointment(id: secondID, startHour: 9, startMinute: 0, duration: 30),
        ])

        let first = try layout(for: firstID, in: layouts)
        let second = try layout(for: secondID, in: layouts)
        let columnWidth = (contentWidth - metrics.overlapColumnSpacing) / 2

        #expect(first.rect.minX == metrics.contentLeadingInset)
        #expect(
            second.rect.minX == metrics.contentLeadingInset + columnWidth
                + metrics.overlapColumnSpacing)
        #expect(first.rect.width == columnWidth)
        #expect(second.rect.width == columnWidth)
    }

    @Test func threeSimultaneousAppointmentsSplitIntoThreeColumns() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let thirdID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let layouts = engine.layout(appointments: [
            appointment(id: firstID, startHour: 9, startMinute: 0, duration: 30),
            appointment(id: secondID, startHour: 9, startMinute: 0, duration: 30),
            appointment(id: thirdID, startHour: 9, startMinute: 0, duration: 30),
        ])

        let first = try layout(for: firstID, in: layouts)
        let second = try layout(for: secondID, in: layouts)
        let third = try layout(for: thirdID, in: layouts)
        let columnWidth = (contentWidth - metrics.overlapColumnSpacing * 2) / 3

        #expect(first.rect.minX == metrics.contentLeadingInset)
        #expect(
            second.rect.minX == metrics.contentLeadingInset + columnWidth
                + metrics.overlapColumnSpacing)
        #expect(
            third.rect.minX == metrics.contentLeadingInset
                + (columnWidth + metrics.overlapColumnSpacing) * 2)
        #expect(first.rect.width == columnWidth)
        #expect(second.rect.width == columnWidth)
        #expect(third.rect.width == columnWidth)
    }

    @Test func staggeredOverlapReusesEndedColumnsWithinSameGroup() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let thirdID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let layouts = engine.layout(appointments: [
            appointment(id: firstID, startHour: 9, startMinute: 0, duration: 30),
            appointment(id: secondID, startHour: 9, startMinute: 15, duration: 30),
            appointment(id: thirdID, startHour: 9, startMinute: 30, duration: 30),
        ])

        let first = try layout(for: firstID, in: layouts)
        let second = try layout(for: secondID, in: layouts)
        let third = try layout(for: thirdID, in: layouts)
        let columnWidth = (contentWidth - metrics.overlapColumnSpacing) / 2

        #expect(first.rect.minX == metrics.contentLeadingInset)
        #expect(
            second.rect.minX == metrics.contentLeadingInset + columnWidth
                + metrics.overlapColumnSpacing)
        #expect(third.rect.minX == first.rect.minX)
        #expect(first.rect.width == columnWidth)
        #expect(second.rect.width == columnWidth)
        #expect(third.rect.width == columnWidth)
    }

    @Test func appointmentsTouchingAtBoundaryDoNotSplitWidth() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let layouts = engine.layout(appointments: [
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
        let layouts = engine.layout(appointments: [
            appointment(id: id, startHour: 9, startMinute: 30, duration: 45)
        ])

        let layout = try layout(for: id, in: layouts)

        #expect(layout.rect.minY == 31)
        #expect(layout.rect.height == 43)
    }

    @Test func timelineScaleMapsTimeBeforeBreakWithinFirstSegment() {
        #expect(scale.yOffset(for: TimeOfDay(10, 30)) == 90)
    }

    @Test func timelineScaleCollapsesTimeDuringBreakToFirstSegmentEnd() {
        #expect(scale.yOffset(for: TimeOfDay(14, 30)) == 240)
    }

    @Test func timelineScaleIncludesBreakHeightAfterBreak() {
        #expect(scale.yOffset(for: TimeOfDay(17, 30)) == 362)
    }

    private var engine: TimelineLayoutEngine {
        TimelineLayoutEngine(
            metrics: metrics,
            availableWidth: availableWidth,
            start: TimeOfDay(9, 0)
        )
    }

    private var contentWidth: CGFloat {
        metrics.contentWidth(availableWidth: availableWidth)
    }

    private var scale: TimelineScale {
        TimelineScale(
            metrics: metrics,
            start: TimeOfDay(9, 0),
            end: TimeOfDay(21, 0),
            breakBlock: BreakBlock(
                start: TimeOfDay(13, 0),
                end: TimeOfDay(16, 0),
                title: "Break"
            ),
            breakHeight: 32
        )
    }

    private func appointment(
        id: UUID,
        startHour: Int,
        startMinute: Int,
        duration: Int
    ) -> Appointment {
        Appointment(
            id: id,
            patientName: "Patient",
            start: Date(timeIntervalSinceReferenceDate: 804_600_000)
                .setTime(startHour, startMinute),
            durationMinutes: duration,
            status: .scheduled
        )
    }

    private func layout(
        for id: UUID,
        in layouts: [AppointmentLayoutInfo]
    ) throws -> AppointmentLayoutInfo {
        try #require(layouts.first { $0.id == id })
    }
}
