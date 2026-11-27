import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct DayCapacityIndicatorTests {
    @Test func mergedSpansCoalesceContiguousAndOverlappingSlotsAndIgnoreBreak() {
        let metrics = DayCapacityMetrics(slots: [
            DayCapacitySlot(startMinute: 9 * 60, endMinute: 10 * 60),
            DayCapacitySlot(startMinute: 10 * 60, endMinute: 10 * 60 + 45),
            DayCapacitySlot(startMinute: 10 * 60 + 15, endMinute: 10 * 60 + 45),
            DayCapacitySlot(startMinute: 12 * 60, endMinute: 12 * 60 + 15),
            DayCapacitySlot(startMinute: 12 * 60 + 15, endMinute: 12 * 60 + 30),
            DayCapacitySlot(startMinute: 12 * 60 + 30, endMinute: 13 * 60),
            // Break-hour appointment must not appear in either shift.
            DayCapacitySlot(startMinute: 13 * 60 + 30, endMinute: 15 * 60),
            DayCapacitySlot(startMinute: 17 * 60, endMinute: 18 * 60),
        ])

        #expect(
            metrics.mergedSpans(in: DayCapacityMetrics.morningRange) == [
                (9 * 60)..<(10 * 60 + 45),
                (12 * 60)..<(13 * 60),
            ]
        )
        #expect(
            metrics.mergedSpans(in: DayCapacityMetrics.eveningRange) == [
                (17 * 60)..<(18 * 60)
            ]
        )
    }

    @Test func pillIntervalsStayWithinShiftBoundsAndCoalesceVisualCollisions() {
        let width: CGFloat = 13.56
        let minPillWidth: CGFloat = 2.8

        // Adjacent 11:00–12:15 and 12:30–13:00 collide after minimum-width clamping at 1:00 PM
        // and should coalesce into one clean capsule ending flush at `width`.
        let colliding = DayCapacityMetrics(slots: [
            DayCapacitySlot(startMinute: 11 * 60, endMinute: 12 * 60 + 15),
            DayCapacitySlot(startMinute: 12 * 60 + 30, endMinute: 13 * 60),
        ])
        let coalesced = colliding.pillIntervals(
            in: DayCapacityMetrics.morningRange,
            width: width,
            minPillWidth: minPillWidth
        )
        #expect(coalesced.count == 1)
        #expect(coalesced[0].upperBound == width)

        // Well-separated slots keep distinct pills within bounds.
        let separated = DayCapacityMetrics(slots: [
            DayCapacitySlot(startMinute: 9 * 60, endMinute: 9 * 60 + 15),
            DayCapacitySlot(startMinute: 12 * 60 + 45, endMinute: 13 * 60),
        ])
        let distinct = separated.pillIntervals(
            in: DayCapacityMetrics.morningRange,
            width: width,
            minPillWidth: minPillWidth
        )
        #expect(distinct.count == 2)
        #expect(distinct[0].lowerBound == 0)
        #expect(distinct[1].upperBound == width)
    }

    @Test func loadWeekStripCoversThreeWeeksAndExcludesCancelledAndUnavailable() async throws {
        let calendar = ClinicDate.calendar
        let database = try testDatabase()
        let selectedDate = try Date("2026-04-22T00:00:00+05:30", strategy: .iso8601)
        let weekStart = selectedDate.startOfWeek(using: calendar)
        let previousWeekDay = weekStart.date(byAddingDays: -2, using: calendar)
        let nextWeekDay = weekStart.date(byAddingDays: 10, using: calendar)
        let outsideDay = weekStart.date(byAddingDays: 15, using: calendar)
        let patientID = UUID()
        let createdAt = try Date("2026-04-01T00:00:00Z", strategy: .iso8601)

        try await database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: patientID,
                    name: "Anjali Desai",
                    phone: nil,
                    dob: nil,
                    gender: nil,
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
            }
            .execute(db)

            let seeds: [(Date, Int, Appointment.Status)] = [
                (previousWeekDay.setTime(9, 0, using: calendar), 60, .completed),
                (selectedDate.setTime(10, 0, using: calendar), 45, .scheduled),
                (selectedDate.setTime(11, 0, using: calendar), 30, .cancelled),
                (nextWeekDay.setTime(17, 0, using: calendar), 60, .scheduled),
                (outsideDay.setTime(10, 0, using: calendar), 30, .scheduled),
            ]
            for (start, duration, status) in seeds {
                let record = try AppointmentRecord.persisted(
                    id: UUID(),
                    patientID: patientID,
                    start: start,
                    durationMinutes: duration,
                    status: status,
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
                try AppointmentRecord.insert { record }.execute(db)
            }

            try UnavailableTimeRecord.insert {
                UnavailableTimeRecord(
                    id: UUID(),
                    label: "Travel",
                    start: selectedDate.setTime(12, 0, using: calendar),
                    durationMinutes: 60,
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
            }
            .execute(db)
        }

        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let model = ScheduleModel()
            try await model.loadWeekStrip(centeredOn: weekStart)

            #expect(
                model.dayCapacitySlots(for: previousWeekDay)
                    == [DayCapacitySlot(startMinute: 9 * 60, endMinute: 10 * 60)]
            )
            #expect(
                model.dayCapacitySlots(for: selectedDate)
                    == [DayCapacitySlot(startMinute: 10 * 60, endMinute: 10 * 60 + 45)]
            )
            #expect(
                model.dayCapacitySlots(for: nextWeekDay)
                    == [DayCapacitySlot(startMinute: 17 * 60, endMinute: 18 * 60)]
            )
            #expect(model.dayCapacitySlots(for: outsideDay).isEmpty)
        }
    }
}
