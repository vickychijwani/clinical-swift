import ClinicalModels
import ClinicalPersistence
import CoreGraphics
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Synchronization
import Testing

@testable import clinical_swift

@MainActor
struct MixedScheduleTests {
    @Test func mixedLayoutUsesStableColumnsAndTypedIdentity() throws {
        let id = UUID()
        let start = Date.now.setTime(9, 0)
        let appointment = Appointment(
            id: id, patientName: "Patient", start: start, durationMinutes: 60, status: .scheduled)
        let block = UnavailableTime(id: id, label: "Travel", start: start, durationMinutes: 60)
        let items: [TimelineItem] = [.unavailableTime(block), .appointment(appointment)]
        let scale = TimelineScale(items: items)
        let engine = TimelineLayoutEngine(availableWidth: 360, scale: scale)
        let two = engine.layout(items: items)
        #expect(two.map(\.id) == [.appointment(id), .unavailableTime(id)])
        #expect(two[0].rect.width == two[1].rect.width)
        #expect(two[0].rect.maxX == two[1].rect.minX)
        let third = TimelineItem.unavailableTime(
            UnavailableTime(start: start.addingTimeInterval(15 * 60), durationMinutes: 60))
        let fourth = TimelineItem.appointment(
            Appointment(
                patientName: "Fourth", start: start.addingTimeInterval(30 * 60),
                durationMinutes: 60, status: .scheduled))
        let layouts = engine.layout(items: items + [third, fourth])
        #expect(Set(layouts.map { $0.rect.minX }).count == 3)
        #expect(layouts[2].rect.minX == layouts[3].rect.minX)
        #expect(
            engine.layout(items: Array((items + [third, fourth]).reversed())).map(\.id)
                == layouts.map(\.id))
        let touching = TimelineItem.unavailableTime(
            UnavailableTime(start: start.addingTimeInterval(60 * 60), durationMinutes: 30))
        let touchLayouts = engine.layout(items: [.appointment(appointment), touching])
        #expect(touchLayouts[0].rect.minX == touchLayouts[1].rect.minX)
        #expect(touchLayouts[0].rect.width == Timeline.metrics.contentWidth(availableWidth: 360))
        let stagger = engine.layout(items: [
            .appointment(
                Appointment(patientName: "A", start: start, durationMinutes: 30, status: .scheduled)
            ),
            .unavailableTime(
                UnavailableTime(start: start.addingTimeInterval(15 * 60), durationMinutes: 30)),
            .unavailableTime(
                UnavailableTime(start: start.addingTimeInterval(30 * 60), durationMinutes: 30)),
        ])
        #expect(stagger[0].rect.minX == stagger[2].rect.minX)
        #expect(stagger[0].rect.maxX == stagger[1].rect.minX)
    }

    @Test func blockStartsExpandBreakAtHalfOpenBoundaries() {
        let day = Date.now
        for (time, expected) in [
            (Bitehaus.break.start, true), (Bitehaus.break.end, false),
            (Bitehaus.break.start + -15, false),
        ] {
            let block = UnavailableTime(start: time.on(date: day), durationMinutes: 60)
            let item = TimelineItem.unavailableTime(block)
            let scale = TimelineScale(items: [item])
            #expect(scale.isBreakExpanded == expected)
            let layout = TimelineLayoutEngine(availableWidth: 360, scale: scale).layout(items: [
                item
            ])[0]
            #expect(
                layout.rect.minY == scale.yOffset(for: time) + Timeline.metrics.verticalCardMargin)
            #expect(layout.rect.height == scale.height(from: time, to: time + 60))
        }
    }

    @Test func widgetReadsMixedItemsAndRefreshesAtFirstEnd() throws {
        let calendar = utcCalendar
        let database = try DatabaseQueue()
        try migrateDatabase(database)
        let now = try instant("2026-10-02T10:30:00Z")
        let patient = Patient(name: "Patient", createdDate: now)
        let appointment = try AppointmentRecord.persisted(
            id: UUID(), patientID: patient.id, start: now, durationMinutes: 60, status: .scheduled,
            createdAt: now, updatedAt: now)
        try database.write { db in
            try PatientRecord.insert { PatientRecord(patient) }.execute(db)
            try AppointmentRecord.insert { appointment }.execute(db)
        }
        let repository = withDependencies {
            $0.calendar = calendar
        } operation: {
            WidgetScheduleRepository(databaseURL: URL(filePath: "/unused"))
        }
        #expect(try repository.snapshot(in: database, at: now).sections[0].items.count == 1)
        let blockStarts = [
            "2026-10-02T10:00:00Z", "2026-10-02T10:30:00Z", "2026-10-03T09:00:00Z",
            "2026-10-04T09:00:00Z", "2026-10-05T09:00:00Z",
        ]
        let blocks = try blockStarts.map { start in
            let date = try instant(start)
            return UnavailableTimeRecord(
                id: UUID(), label: " \n ", start: date, durationMinutes: 30, createdAt: now,
                updatedAt: now)
        }
        try database.write { db in
            for block in blocks { try UnavailableTimeRecord.insert { block }.execute(db) }
        }
        let snapshot = try repository.snapshot(in: database, at: now)
        #expect(snapshot.sections.map { $0.items.count } == [2, 1, 1])
        #expect(
            snapshot.sections[0].items.map(\.id) == [
                .unavailableTime(blocks[1].id), .appointment(appointment.id),
            ])
        #expect(snapshot.nextRefreshDate(using: calendar) == now.addingTimeInterval(30 * 60))
        #expect(
            snapshot.sections[0].items[0].widgetURL(using: calendar)
                == ClinicalURL.schedule(ScheduleDay(date: now, calendar: calendar)).url)
        #expect(
            snapshot.sections[0].items[1].widgetURL(using: calendar)
                == ClinicalURL.appointment(appointment.id).url)
        let later = try repository.snapshot(in: database, at: now.addingTimeInterval(30 * 60))
        #expect(later.sections[0].items.count == 1)
        #expect(later.nextRefreshDate(using: calendar) == now.addingTimeInterval(60 * 60))
        let night = try repository.snapshot(in: database, at: now.addingTimeInterval(2 * 60 * 60))
        #expect(night.sections[0].items.isEmpty)
        #expect(night.nextRefreshDate(using: calendar) == (try instant("2026-10-03T00:00:00Z")))
        #expect(blocks[0].unavailableTime.displayLabel == "Blocked")
    }

    @Test func mixedWidgetCountsUseTheSameCapacityAndOnlyLastSectionOverflows() throws {
        let start = try instant("2026-10-02T10:00:00Z")
        let appointments = (0..<6).map { index in
            Appointment(
                patientName: "Patient", start: start.addingTimeInterval(Double(index) * 60),
                durationMinutes: 30, status: .scheduled)
        }
        let blocks = appointments.map { UnavailableTime(start: $0.start, durationMinutes: 30) }
        let appointmentOnly = WidgetScheduleSection(
            date: start, isToday: true, items: appointments.map(TimelineItem.appointment))
        let mixed = WidgetScheduleSection(
            date: start, isToday: true,
            items: zip(appointments, blocks).map { appointment, block in
                [TimelineItem.appointment(appointment), .unavailableTime(block)]
            }.flatMap { $0 })
        let blockOnly = WidgetScheduleSection(
            date: start, isToday: true, items: blocks.map(TimelineItem.unavailableTime))
        let planner = WidgetLayoutPlanner()
        #expect(
            planner.plan(sections: [appointmentOnly], availableHeight: 240).sections
                == planner.plan(sections: [blockOnly], availableHeight: 240).sections)
        let plan = planner.plan(
            sections: [mixed, appointmentOnly, blockOnly], availableHeight: 240)
        #expect(plan.contentHeight <= 240)
        for section in plan.sections.dropLast() {
            #expect(
                !section.rows.contains {
                    if case .overflow = $0 { return true }
                    return false
                })
        }
        #expect(mixed.overflowText(hiddenCount: 1) == "1 more item")
        #expect(mixed.overflowText(hiddenCount: 4) == "4 more items")
        #expect(appointmentOnly.overflowText(hiddenCount: 1) == "1 more appointment")
    }

    @Test func blockNavigationAndEditorHandoffsRejectOldResults() throws {
        let date = try instant("2026-10-02T09:00:00Z")
        try withDependencies {
            $0.calendar = utcCalendar
        } operation: {
            let router = Router(selectedScheduleDate: date)
            router.requestUnavailableTimeCreation()
            let editor = try #require(router.unavailableTimeEditorRequest)
            router.presentationDidAppear(editor.id)
            router.requestAppointmentBooking()
            #expect(router.activePresentation == nil)
            router.presentationDidDismiss()
            #expect(router.appointmentBookingRequest != nil)
            router.finishScheduleEditor(editor.id, date: date.addingTimeInterval(24 * 60 * 60))
            #expect(router.selectedScheduleDate == utcCalendar.startOfDay(for: date))
            #expect(router.appointmentBookingRequest != nil)
            let block = UnavailableTime(
                start: date.addingTimeInterval(24 * 60 * 60), durationMinutes: 60)
            #expect(router.open((try #require(ClinicalURL.unavailableTime(block.id).url))))
            let first = try #require(router.unavailableTimeNavigationRequest)
            router.openExternalSchedule(ScheduleDay(date: date, calendar: utcCalendar))
            router.completeUnavailableTimeNavigation(first, block: block)
            #expect(router.selectedScheduleDate == utcCalendar.startOfDay(for: date))
            router.openUnavailableTime(block.id)
            router.completeUnavailableTimeNavigation(
                try #require(router.unavailableTimeNavigationRequest), block: block)
            #expect(router.selectedScheduleDate == utcCalendar.startOfDay(for: block.start))
            #expect(router.unavailableTimeEditorRequest == nil)
            router.openUnavailableTime(UUID())
            router.completeUnavailableTimeNavigation(
                try #require(router.unavailableTimeNavigationRequest), block: nil)
            #expect(router.navigationErrorMessage != nil)
            #expect(
                ClinicalURL((try #require(ClinicalURL.unavailableTime(block.id).url)))
                    == .unavailableTime(block.id))
            #expect(
                ClinicalURL(try #require(URL(string: "clinical://unavailable-times/invalid")))
                    == nil)
        }
    }

    @Test func observedBlocksPageWithoutChangingBookingAvailability() async throws {
        let database = try DatabaseQueue()
        try migrateDatabase(database)
        let date = try instant("2026-10-02T09:00:00Z")
        try await withDependencies {
            $0.defaultDatabase = database
            $0.calendar = utcCalendar
            $0.date.now = date
        } operation: {
            let model = ScheduleModel()
            try await model.loadVisibleDays(centeredOn: date, dayRadius: 3)
            let patient = Patient(name: "Patient", createdDate: date)
            try await database.write { db in
                try PatientRecord.insert { PatientRecord(patient) }.execute(db)
            }
            let booking = AppointmentBookingModel(selectedDate: date, selectedPatient: patient) {
                _ in
            }
            booking.updateAppointments(model.appointments(for: date), for: date)
            let before = booking.draft.start
            let blocks = (-3...4).map { day in
                UnavailableTimeRecord(
                    id: UUID(), label: nil,
                    start: date.addingTimeInterval(Double(day) * 24 * 60 * 60),
                    durationMinutes: 120, createdAt: date, updatedAt: date)
            }
            try await database.write { db in
                for block in blocks { try UnavailableTimeRecord.insert { block }.execute(db) }
            }
            for _ in 0..<100 {
                if !model.unavailableTimes(for: date).isEmpty { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(model.unavailableTimes(for: date).count == 1)
            #expect(model.unavailableTimes(for: blocks[0].start).count == 1)
            #expect(model.unavailableTimes(for: blocks[7].start).isEmpty)
            booking.updateAppointments(model.appointments(for: date), for: date)
            #expect(booking.draft.start == before)
            #expect(await booking.saveAppointment())
            #expect(
                try await database.read { db in try AppointmentRecord.count().fetchOne(db) } == 1)
            try await model.loadVisibleDays(centeredOn: blocks[7].start, dayRadius: 3)
            #expect(model.unavailableTimes(for: blocks[7].start).count == 1)
            #expect(model.unavailableTimes(for: blocks[0].start).isEmpty)
        }
    }

    @Test func committedBlockWritesReloadWidgetsAndRollbacksDoNot() async throws {
        let database = try DatabaseQueue()
        try migrateDatabase(database)
        let reloads = Mutex(0)
        let invalidator = WidgetTimelineInvalidator(
            database: database,
            reload: {
                reloads.withLock { $0 += 1 }
            })
        let start = try instant("2026-10-02T09:00:00Z")
        let block = UnavailableTimeRecord(
            id: UUID(), start: start, durationMinutes: 60, createdAt: start, updatedAt: start)
        try await database.write { db in try UnavailableTimeRecord.insert { block }.execute(db) }
        try await database.write { db in
            try UnavailableTimeRecord.find(block.id).update { $0.label = #bind("Travel") }.execute(
                db)
        }
        try await database.write { db in
            try UnavailableTimeRecord.find(block.id).delete().execute(db)
        }
        for _ in 0..<100 {
            if reloads.withLock({ $0 }) == 4 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(reloads.withLock { $0 } == 4)
        do {
            try await database.write { db in
                try UnavailableTimeRecord.insert { block }.execute(db)
                throw UnavailableTimeError.invalidTime
            }
            Issue.record("The transaction should fail.")
        } catch UnavailableTimeError.invalidTime {}
        for _ in 0..<5 { await Task.yield() }
        #expect(reloads.withLock { $0 } == 4)
        withExtendedLifetime(invalidator) {}
    }

    @Test func calendarBlockURLLoadsItsStoredDate() async throws {
        let database = try DatabaseQueue()
        try migrateDatabase(database)
        let start = try instant("2026-10-04T14:00:00Z")
        let block = UnavailableTimeRecord(
            id: UUID(), start: start, durationMinutes: 60, createdAt: start, updatedAt: start)
        try await database.write { db in try UnavailableTimeRecord.insert { block }.execute(db) }
        try await withDependencies {
            $0.calendar = utcCalendar
            $0.defaultDatabase = database
        } operation: {
            let router = Router()
            router.requestUnavailableTimeCreation()
            router.openUnavailableTime(block.id)
            let request = try #require(router.unavailableTimeNavigationRequest)
            await router.resolveUnavailableTime(request)
            #expect(router.selectedScheduleDate == utcCalendar.startOfDay(for: block.start))
            #expect(router.activePresentation == nil)
            router.openUnavailableTime(UUID())
            await router.resolveUnavailableTime(
                try #require(router.unavailableTimeNavigationRequest))
            #expect(router.navigationErrorMessage == "This unavailable time no longer exists.")
        }
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }
    private func instant(_ string: String) throws -> Date { try Date(string, strategy: .iso8601) }
}
