import ClinicalModels
import Foundation
import Testing

@testable import clinical_swift

struct WidgetLayoutPlannerTests {
    @Test func denseTodayFitsAllRowsAtAdaptiveHeight() {
        let sections = sections(appointmentCounts: [8, 0, 0])
        let plan = WidgetLayoutPlanner().plan(
            sections: sections,
            availableHeight: 300
        )

        #expect(plan.sections.count == 1)
        #expect(plan.sections[0].sourceIndex == 0)
        #expect(
            plan.sections[0].rows == [
                .item(0),
                .item(1),
                .item(2),
                .item(3),
                .item(4),
                .item(5),
                .item(6),
                .item(7),
            ])
        #expect(plan.rowHeight == 27)
        #expect(plan.contentHeight == 300)
        #expect(plan.trailingSpace == 0)
    }

    @Test func laterSectionAppearsOnlyAfterEarlierSectionsAreComplete() {
        let plan = WidgetLayoutPlanner().plan(
            sections: sections(appointmentCounts: [2, 6, 1]),
            availableHeight: 300
        )

        #expect(plan.sections.map(\.sourceIndex) == [0, 1])
        #expect(plan.sections[0].rows == [.item(0), .item(1)])
        #expect(
            plan.sections[1].rows == [
                .item(0),
                .item(1),
                .item(2),
                .item(3),
                .overflow(hiddenCount: 2),
            ])
        #expect(plan.contentHeight == 300)
    }

    @Test func sparseThreeDayContentKeepsAllConsecutiveSectionsAndPermitsTrailingSpace() {
        let plan = WidgetLayoutPlanner().plan(
            sections: sections(appointmentCounts: [1, 0, 0]),
            availableHeight: 300
        )

        #expect(plan.sections.map(\.sourceIndex) == [0, 1, 2])
        #expect(plan.rowHeight == WidgetLayoutConfiguration.standard.maximumRowHeight)
        #expect(plan.trailingSpace > 0)
    }

    private func sections(appointmentCounts: [Int]) -> [WidgetScheduleSection] {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return appointmentCounts.enumerated().compactMap { offset, count in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }
            let appointments = (0..<count).map { index in
                Appointment(
                    id: UUID(),
                    patientName: "Patient \(index)",
                    start: date.addingTimeInterval(Double(index) * 60 * 60),
                    durationMinutes: 45,
                    status: .scheduled
                )
            }
            return WidgetScheduleSection(
                date: date,
                isToday: offset == 0,
                items: appointments.map(TimelineItem.appointment)
            )
        }
    }
}
