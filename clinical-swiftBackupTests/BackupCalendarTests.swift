import Dependencies
import Foundation
import GRDB
import Testing

@testable import clinical_swift

@MainActor
struct BackupCalendarTests {
    @Test func recoveryLeavesUnlinkedRecordsOutOfCalendar() async throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await withDependencies {
            $0.calendar = Calendar(identifier: .gregorian)
        } operation: {
            let database = try BackupFixture.database(at: directory.appending(path: "source.db"))
            defer { try? database.close() }
            try await database.write { db in
                // These records model pre-integration data or samples excluded from sync.
                try db.execute(
                    sql:
                        "DELETE FROM appointmentCalendarSync WHERE appointmentID = '20000000-0000-0000-0000-000000000001'"
                )
                try db.execute(
                    sql:
                        "DELETE FROM unavailableTimeCalendarSync WHERE unavailableTimeID = '30000000-0000-0000-0000-000000000001'"
                )
            }
            let before = try BackupFixture.contents(database)
            try BackupRestore.prepareCalendar(
                database, cutoff: Date("2026-10-04T00:00:00Z", strategy: .iso8601))
            let fake = RecoveryCalendar()
            let coordinator = CalendarSyncCoordinator(
                database: database, calendarClient: fake.client,
                contactClient: .init(nameForPhone: { _ in nil }))
            await coordinator.activate()
            #expect(fake.payloads.isEmpty)
            #expect(fake.deleted.count == 2)
            let after = try BackupFixture.contents(database)
            for table in ["patients", "appointments", "unavailableTimes"] {
                #expect(after[table] == before[table])
            }
            #expect(
                try await database.read { db in
                    try Int.fetchOne(
                        db,
                        sql:
                            "SELECT count(*) FROM appointmentCalendarSync WHERE appointmentID = '20000000-0000-0000-0000-000000000001'"
                    )
                } == 0)
            #expect(
                try await database.read { db in
                    try Int.fetchOne(
                        db,
                        sql:
                            "SELECT count(*) FROM unavailableTimeCalendarSync WHERE unavailableTimeID = '30000000-0000-0000-0000-000000000001'"
                    )
                } == 0)
        }
    }

    @Test func recoveryAppliesSnapshotValuesAndRetriesEachFailedItem() async throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        try await withDependencies {
            $0.calendar = calendar
        } operation: {
            let database = try BackupFixture.database(at: directory.appending(path: "source.db"))
            defer { try? database.close() }
            let cutoff = try Date("2026-10-04T00:00:00Z", strategy: .iso8601)
            try BackupRestore.prepareCalendar(database, cutoff: cutoff)
            let fake = RecoveryCalendar()
            let coordinator = CalendarSyncCoordinator(
                database: database, calendarClient: fake.client,
                contactClient: .init(nameForPhone: { _ in nil }))
            await coordinator.activate()
            #expect(
                fake.payloads.contains {
                    $0.title == "Synthetic WAL update"
                        && $0.start == (try? Date("2026-10-10T10:30:00Z", strategy: .iso8601))
                })
            #expect(fake.links.allSatisfy { $0.recoveryCutoff == cutoff })
            #expect(fake.links.contains { $0.eventIdentifier == "old-event-id" })
            #expect(fake.payloads.count >= 2)
            #expect(fake.deleted.count == 2)
            let pendingAfterFailure = try await database.read {
                try Int.fetchOne(
                    $0, sql: "SELECT count(*) FROM appointmentCalendarSync WHERE needsSync = 1")
            }
            #expect(pendingAfterFailure == 1)
            let beforeRetry = fake.payloads.count
            fake.failAppointment = false
            await coordinator.activate()
            #expect(fake.payloads.count > beforeRetry)
            #expect(
                try await database.read {
                    try String.fetchOne(
                        $0,
                        sql:
                            "SELECT eventIdentifier FROM appointmentCalendarSync WHERE appointmentID = '20000000-0000-0000-0000-000000000001'"
                    )
                } == "recovered-id")
            #expect(
                try await database.read {
                    try Int.fetchOne($0, sql: "SELECT count(*) FROM clinicalCalendarRecovery")
                } == 0)
            #expect(
                try await database.read {
                    try Int.fetchOne($0, sql: "SELECT count(*) FROM appointments")
                } == 3)
        }
    }

    @Test func recoverySearchIncludesMovedEventsAndDistantFutureLinks() throws {
        let cutoff = try Date("2026-10-04T00:00:00Z", strategy: .iso8601)
        let movedEvent = try Date("2027-06-01T00:00:00Z", strategy: .iso8601)
        let futureLink = try Date("2040-01-01T00:00:00Z", strategy: .iso8601)
        let horizon = CalendarRecoveryWindow.horizon(
            knownStarts: [futureLink], now: BackupFixture.capturedAt)
        var start = cutoff
        var ranges: [DateInterval] = []
        while start < horizon {
            let end = CalendarRecoveryWindow.queryEnd(from: start, through: horizon)
            ranges.append(DateInterval(start: start, end: end))
            start = end
        }
        #expect(ranges.allSatisfy { $0.duration <= 3 * 365 * 86_400 })
        #expect(ranges.contains { $0.contains(movedEvent) })
        #expect(ranges.contains { $0.contains(futureLink) })
        #expect(!ranges.contains { $0.contains(cutoff.addingTimeInterval(-1)) })
    }

    @Test func retentionKeepsLatestPairEvenWhenAllCopiesAreOld() {
        let now = BackupFixture.capturedAt
        func pair(_ name: String, age: TimeInterval) -> DriveBackupPair {
            DriveBackupPair(
                database: DriveBackupFile(id: name + ".db"),
                manifest: DriveBackupFile(id: name + ".json"),
                capturedAt: now.addingTimeInterval(-age))
        }
        let latest = pair("latest", age: 40 * 86400)
        let old = pair("old", age: 41 * 86400)
        #expect(
            BackupRetention.fileIDsToDelete([old, latest], at: now, lastSuccess: nil) == [
                "old.json", "old.db",
            ])
        #expect(BackupRetention.fileIDsToDelete([latest], at: now, lastSuccess: nil).isEmpty)
        #expect(
            BackupRetention.fileIDsToDelete(
                [pair("today", age: 0), pair("boundary", age: 30 * 86400)], at: now,
                lastSuccess: nil
            ).isEmpty)
    }
}

@MainActor
private final class RecoveryCalendar {
    enum Failure: Error { case write }
    var failAppointment = true
    var payloads: [CalendarEventPayload] = []
    var links: [CalendarEventLink] = []
    var deleted: [URL] = []

    var client: CalendarClient {
        CalendarClient(
            requestFullAccess: { true }, resolveTargetCalendar: { true },
            replaceEvent: { [self] link, payload in
                payloads.append(payload)
                links.append(link)
                if payload.url.host == "appointments", failAppointment { throw Failure.write }
                // A different event identifier models recovery on another device.
                return CalendarEventLink(eventIdentifier: "recovered-id", eventStart: payload.start)
            },
            deleteEvent: { [self] link, marker, _ in
                links.append(link)
                deleted.append(marker)
            })
    }
}
