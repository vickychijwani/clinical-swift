import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct UnavailableTimeCalendarTests {
    @Test func createReplaceDeleteUsesBlockContractWithoutContacts() async throws {
        let database = try testDatabase()
        let block = try insertBlock(into: database, label: "Travel")
        let recorder = BlockCalendarRecorder()
        let coordinator = makeCoordinator(database, recorder)
        try await activate(coordinator)
        let first = try #require(recorder.payloads.first)
        #expect(first.title == "Blocked: Travel")
        #expect(first.start == block.start)
        #expect(first.end == block.start.addingTimeInterval(60 * 60))
        #expect(first.notes == "")
        #expect(first.url == ClinicalURL.unavailableTime(block.id).url)
        #expect(try syncRow(block.id, database)?.needsSync == false)
        try await database.write { db in
            try UnavailableTimeRecord.find(block.id).update {
                $0.label = #bind(nil, as: String?.self)
                $0.durationMinutes = 30
            }.execute(db)
        }
        try await activate(coordinator)
        try await waitUntil { recorder.payloads.last?.title == "Blocked" }
        #expect(recorder.payloads.last?.title == "Blocked")
        #expect(recorder.payloads.last?.end == block.start.addingTimeInterval(30 * 60))
        #expect(recorder.links.last?.eventIdentifier == "event-1")
        try await database.write { db in
            try UnavailableTimeRecord.find(block.id).delete().execute(db)
        }
        try await activate(coordinator)
        try await waitUntil { try syncRow(block.id, database) == nil }
        #expect(recorder.deletions.last == ClinicalURL.unavailableTime(block.id).url)
        #expect(try syncRow(block.id, database) == nil)
    }

    @Test func deleteBeforeDeliveryDoesNotCreateAnEvent() async throws {
        let database = try testDatabase()
        let block = try insertBlock(into: database)
        try await database.write { db in
            try UnavailableTimeRecord.find(block.id).delete().execute(db)
        }
        let recorder = BlockCalendarRecorder()
        let coordinator = makeCoordinator(database, recorder)
        try await activate(coordinator)
        #expect(recorder.payloads.isEmpty)
        #expect(recorder.deletions == [ClinicalURL.unavailableTime(block.id).url])
        #expect(try syncRow(block.id, database) == nil)
    }

    @Test func matchingUUIDsKeepIndependentLinksAndAppointmentWorkRunsFirst() async throws {
        let database = try testDatabase()
        let block = try insertBlock(into: database)
        let patient = Patient(name: "Patient", createdDate: block.start)
        let appointment = try AppointmentRecord.persisted(
            id: block.id, patientID: patient.id, start: block.start, durationMinutes: 30,
            status: .scheduled, createdAt: block.start, updatedAt: block.start)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient) }.execute(db)
            try AppointmentRecord.insert { appointment }.execute(db)
        }
        let recorder = BlockCalendarRecorder()
        recorder.failureURL = ClinicalURL.unavailableTime(block.id).url
        let coordinator = makeCoordinator(database, recorder)
        try await activate(coordinator)
        #expect(recorder.payloads.first?.url == ClinicalURL.appointment(block.id).url)
        #expect(try syncRow(block.id, database)?.needsSync == true)
        #expect(
            try await database.read { db in
                try AppointmentCalendarSyncRecord.where { $0.appointmentID.eq(block.id) }.fetchOne(
                    db)?.needsSync
            } == false)
        recorder.failureURL = nil
        try await activate(coordinator)
        #expect(try syncRow(block.id, database)?.eventIdentifier != "event-1")
        #expect(try syncRow(block.id, database)?.needsSync == false)
    }

    @Test(arguments: [(false, true), (true, false)])
    func permissionOrTargetFailureStaysPendingAndRetriesAfterRestart(
        _ granted: Bool, _ target: Bool
    ) async throws {
        let database = try testDatabase()
        let block = try insertBlock(into: database)
        let denied = BlockCalendarRecorder()
        denied.granted = granted
        denied.target = target
        try await activate(makeCoordinator(database, denied))
        #expect(denied.payloads.isEmpty)
        #expect(try syncRow(block.id, database)?.needsSync == true)
        let retry = BlockCalendarRecorder()
        try await activate(makeCoordinator(database, retry))
        #expect(retry.payloads.count == 1)
        #expect(try syncRow(block.id, database)?.needsSync == false)
    }

    @Test func newerChangesKeepCreatedLinkForPendingRetry() async throws {
        let database = try testDatabase()
        let block = try insertBlock(into: database)
        let recorder = BlockCalendarRecorder()
        recorder.onReplace = { index in
            guard index == 1 else { throw BlockCalendarTestError.writeFailed }
            try await database.write { db in
                try UnavailableTimeRecord.find(block.id).update { $0.label = #bind("Changed") }
                    .execute(db)
            }
        }
        let coordinator = makeCoordinator(database, recorder)
        try await activate(coordinator)
        let row = try #require(try syncRow(block.id, database))
        #expect(row.revision == 2)
        #expect(row.needsSync)
        #expect(row.eventIdentifier == "event-1")
        #expect(recorder.links.last?.eventIdentifier == "event-1")
        recorder.onReplace = nil
        try await activate(coordinator)
        #expect(recorder.payloads.last?.title == "Blocked: Changed")
        #expect(try syncRow(block.id, database)?.needsSync == false)
    }

    @Test func deletionDuringReplacementUsesTheCreatedEventLink() async throws {
        let database = try testDatabase()
        let block = try insertBlock(into: database)
        let recorder = BlockCalendarRecorder()
        recorder.onReplace = { index in
            guard index == 1 else { return }
            try await database.write { db in
                try UnavailableTimeRecord.find(block.id).delete().execute(db)
            }
        }
        let coordinator = makeCoordinator(database, recorder)
        try await activate(coordinator)
        #expect(recorder.payloads.count == 1)
        #expect(recorder.deletedLinks.first?.eventIdentifier == "event-1")
        #expect(try syncRow(block.id, database) == nil)
    }

    @Test func staleDeletionCannotClearRecreatedBlockWork() async throws {
        let database = try testDatabase()
        let block = try insertBlock(into: database)
        try await database.write { db in
            try UnavailableTimeRecord.find(block.id).delete().execute(db)
        }
        let recorder = BlockCalendarRecorder()
        recorder.onDelete = {
            try await database.write { db in try UnavailableTimeRecord.insert { block }.execute(db)
            }
        }
        let coordinator = makeCoordinator(database, recorder)
        try await activate(coordinator)
        #expect(recorder.payloads.count == 1)
        #expect(try syncRow(block.id, database)?.needsSync == false)
        #expect(try syncRow(block.id, database)?.revision == 3)
    }

    @Test func linkPersistenceFailureKeepsPendingWork() async throws {
        let database = try testDatabase()
        let block = try insertBlock(into: database)
        try await database.write { db in
            try db.execute(
                sql:
                    "CREATE TRIGGER reject_event_link BEFORE UPDATE OF eventIdentifier ON unavailableTimeCalendarSync BEGIN SELECT RAISE(ABORT, 'test failure'); END"
            )
        }
        let recorder = BlockCalendarRecorder()
        let coordinator = makeCoordinator(database, recorder)
        try await activate(coordinator)
        #expect(recorder.payloads.count == 1)
        #expect(try syncRow(block.id, database)?.needsSync == true)
        try await database.write { db in try db.execute(sql: "DROP TRIGGER reject_event_link") }
        try await activate(coordinator)
        #expect(recorder.payloads.last?.url == recorder.payloads.first?.url)
        #expect(try syncRow(block.id, database)?.needsSync == false)
    }

    @Test func oneFailedBlockDoesNotStopTheNextBlock() async throws {
        let database = try testDatabase()
        let failed = try insertBlock(into: database, label: "Failed")
        let next = try insertBlock(into: database, label: "Next")
        try await database.write { db in
            try UnavailableTimeCalendarSyncRecord.where { $0.unavailableTimeID.eq(failed.id) }
                .update {
                    $0.updatedAt = failed.start
                }.execute(db)
            try UnavailableTimeCalendarSyncRecord.where { $0.unavailableTimeID.eq(next.id) }.update
            {
                $0.updatedAt = next.start.addingTimeInterval(60)
            }.execute(db)
        }
        let recorder = BlockCalendarRecorder()
        recorder.failureURL = ClinicalURL.unavailableTime(failed.id).url
        try await activate(makeCoordinator(database, recorder))
        #expect(recorder.payloads.first?.title == "Blocked: Failed")
        #expect(try syncRow(failed.id, database)?.needsSync == true)
        #expect(try syncRow(next.id, database)?.needsSync == false)
    }

    @Test func recoveryAdoptsEmptyNotesAndRejectsChangedOrOtherSourceEvents() throws {
        let start = try Date("2026-10-02T11:00:00Z", strategy: .iso8601)
        let id = UUID()
        let url = try #require(ClinicalURL.unavailableTime(id).url)
        let payload = CalendarEventPayload(
            title: "Blocked", start: start, end: start.addingTimeInterval(3600), notes: "", url: url
        )
        #expect(
            payload.matchesEvent(
                title: "Blocked", start: start, end: payload.end, notes: nil, url: url))
        #expect(
            payload.matchesEvent(
                title: "Blocked", start: start.addingTimeInterval(0.5), end: payload.end, notes: "",
                url: url))
        #expect(
            !payload.matchesEvent(
                title: "Changed", start: start, end: payload.end, notes: nil, url: url))
        #expect(
            !payload.matchesEvent(
                title: "Blocked", start: start, end: payload.end, notes: "Manual notes", url: url))
        #expect(
            !payload.matchesEvent(
                title: "Blocked", start: start, end: payload.end, notes: nil,
                url: ClinicalURL.appointment(id).url))
        #expect(
            !payload.matchesEvent(
                title: "Blocked", start: nil, end: payload.end, notes: nil, url: url))
    }

    private func waitUntil(_ condition: () throws -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while try !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(try condition(), "Calendar work did not finish within two seconds.")
    }

    private func insertBlock(into database: DatabaseQueue, label: String? = nil) throws
        -> UnavailableTimeRecord
    {
        let start = try Date("2026-10-02T11:00:00Z", strategy: .iso8601)
        let block = UnavailableTimeRecord(
            id: UUID(), label: label, start: start, durationMinutes: 60, createdAt: start,
            updatedAt: start)
        try database.write { db in try UnavailableTimeRecord.insert { block }.execute(db) }
        return block
    }

    private func syncRow(_ id: UUID, _ database: DatabaseQueue) throws
        -> UnavailableTimeCalendarSyncRecord?
    {
        try database.read { db in
            try UnavailableTimeCalendarSyncRecord.where { $0.unavailableTimeID.eq(id) }.fetchOne(db)
        }
    }

    private func makeCoordinator(_ database: DatabaseQueue, _ recorder: BlockCalendarRecorder)
        -> CalendarSyncCoordinator
    {
        withDependencies {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            $0.calendar = calendar
        } operation: {
            CalendarSyncCoordinator(
                database: database, calendarClient: recorder.client,
                contactClient: AppointmentContactClient { _ in
                    Issue.record("A block must not request a contact name.")
                    return nil
                })
        }
    }

    private func activate(_ coordinator: CalendarSyncCoordinator) async throws {
        var finished = false
        let activation = Task {
            await withDependencies {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .gmt
                $0.calendar = calendar
            } operation: {
                await coordinator.activate()
            }
            finished = true
        }
        defer { activation.cancel() }
        try await waitUntil { finished }
        await activation.value
    }
}

@MainActor
private final class BlockCalendarRecorder {
    var granted = true
    var target = true
    var failureURL: URL?
    var onReplace: ((Int) async throws -> Void)?
    var onDelete: (() async throws -> Void)?
    var payloads: [CalendarEventPayload] = []
    var links: [CalendarEventLink] = []
    var deletions: [URL] = []
    var deletedLinks: [CalendarEventLink] = []

    var client: CalendarClient {
        CalendarClient(
            requestFullAccess: { self.granted }, resolveTargetCalendar: { self.target },
            replaceEvent: { link, payload in
                self.links.append(link)
                self.payloads.append(payload)
                let index = self.payloads.count
                if payload.url == self.failureURL { throw BlockCalendarTestError.writeFailed }
                try await self.onReplace?(index)
                return CalendarEventLink(
                    eventIdentifier: "event-\(index)", eventStart: payload.start)
            },
            deleteEvent: { link, url, _ in
                self.deletions.append(url)
                self.deletedLinks.append(link)
                let onDelete = self.onDelete
                self.onDelete = nil
                try await onDelete?()
            })
    }
}

private enum BlockCalendarTestError: Error { case writeFailed }
