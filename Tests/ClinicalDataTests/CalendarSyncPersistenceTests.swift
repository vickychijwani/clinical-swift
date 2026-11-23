import ClinicalModels
import ClinicalPersistence
import Foundation
import GRDB
import SQLiteData
import Testing

struct CalendarSyncPersistenceTests {
    @Test func prepareCalendarRecoveryEnforcesCutoffTombstonesAndUnlinkedRecords() async throws {
        let db = try testDatabase()
        let cutoff = try iso("2026-10-04T00:00:00Z")
        let patientID = try seedPatient(db, at: cutoff)

        let boundaryAppt = try seedAppointment(
            db, patientID, start: iso("2026-10-03T23:30:00Z"), duration: 30)
        let oldAppt = try seedAppointment(
            db, patientID, start: iso("2026-10-03T23:29:00Z"), duration: 30)
        let unlinkedAppt = try seedAppointment(
            db, patientID, start: iso("2026-10-05T10:00:00Z"), duration: 30)
        let recentTombstone = UUID()
        let oldTombstone = UUID()
        let nilTombstone = UUID()

        let boundaryBlock = try seedBlock(db, start: iso("2026-10-03T23:45:00Z"), duration: 30)
        let oldBlock = try seedBlock(db, start: iso("2026-10-03T23:00:00Z"), duration: 59)
        let unlinkedBlock = try seedBlock(db, start: iso("2026-10-06T09:00:00Z"), duration: 60)
        let blockTombstone = UUID()

        try await db.write { db in
            try updateOutbox(
                .appointment(boundaryAppt), eventID: "appt-ok",
                eventStart: iso("2026-10-01T00:00:00Z"), needsSync: false, revision: 4, in: db)
            try updateOutbox(
                .appointment(oldAppt), eventID: "appt-old", eventStart: iso("2026-10-10T00:00:00Z"),
                needsSync: true, revision: 2, in: db)
            try AppointmentCalendarSyncRecord.where { $0.appointmentID.eq(unlinkedAppt) }.delete()
                .execute(db)

            try insertOutbox(
                .appointment(recentTombstone), eventID: "t-ok", eventStart: cutoff,
                needsSync: false, revision: 3, at: cutoff, in: db)
            try insertOutbox(
                .appointment(oldTombstone), eventID: "t-old",
                eventStart: iso("2026-10-03T23:59:59Z"), needsSync: true, revision: 5, at: cutoff,
                in: db)
            try insertOutbox(
                .appointment(nilTombstone), eventID: nil, eventStart: nil, needsSync: true,
                revision: 1, at: cutoff, in: db)

            try updateOutbox(
                .unavailableTime(boundaryBlock), eventID: "blk-ok",
                eventStart: iso("2026-10-01T00:00:00Z"), needsSync: false, revision: 2, in: db)
            try updateOutbox(
                .unavailableTime(oldBlock), eventID: "blk-old",
                eventStart: iso("2026-10-10T00:00:00Z"), needsSync: true, revision: 7, in: db)
            try UnavailableTimeCalendarSyncRecord.where { $0.unavailableTimeID.eq(unlinkedBlock) }
                .delete().execute(db)
            try insertOutbox(
                .unavailableTime(blockTombstone), eventID: "blk-t",
                eventStart: iso("2026-10-04T01:00:00Z"), needsSync: false, revision: 1, at: cutoff,
                in: db)
        }

        try db.prepareCalendarRecovery(cutoff: cutoff)

        let pending = try await db.fetchPendingCalendarSyncWork()
        #expect(
            Set(pending.map(\.source)) == [
                .appointment(boundaryAppt), .appointment(recentTombstone),
                .unavailableTime(boundaryBlock), .unavailableTime(blockTombstone),
            ])
        #expect(pending.allSatisfy { $0.recoveryCutoff == cutoff })

        try await db.read { db in
            let boundaryRow = try #require(try appointmentOutbox(boundaryAppt, in: db))
            #expect(
                boundaryRow.needsSync && boundaryRow.revision == 5
                    && boundaryRow.eventIdentifier == "appt-ok")

            let oldRow = try #require(try appointmentOutbox(oldAppt, in: db))
            #expect(
                !oldRow.needsSync && oldRow.revision == 3 && oldRow.eventIdentifier == "appt-old")

            let oldTombstoneRow = try #require(try appointmentOutbox(oldTombstone, in: db))
            #expect(
                !oldTombstoneRow.needsSync && oldTombstoneRow.revision == 6
                    && oldTombstoneRow.eventIdentifier == "t-old")

            let nilTombstoneRow = try #require(try appointmentOutbox(nilTombstone, in: db))
            #expect(!nilTombstoneRow.needsSync && nilTombstoneRow.revision == 2)

            #expect(try appointmentOutbox(unlinkedAppt, in: db) == nil)
            #expect(try blockOutbox(unlinkedBlock, in: db) == nil)

            let oldBlockRow = try #require(try blockOutbox(oldBlock, in: db))
            #expect(!oldBlockRow.needsSync && oldBlockRow.revision == 8)
            #expect(try recoveryCount(in: db) == 4)
        }

        // Re-running preparation with a later cutoff clears earlier recovery rows.
        let laterCutoff = try iso("2026-10-04T00:30:00Z")
        try db.prepareCalendarRecovery(cutoff: laterCutoff)
        let laterPending = try await db.fetchPendingCalendarSyncWork()
        #expect(laterPending.map(\.source) == [.unavailableTime(blockTombstone)])
        #expect(laterPending.first?.recoveryCutoff == laterCutoff)
        #expect(try await db.read { try recoveryCount(in: $0) } == 1)
    }

    @Test func eligibilityCheckCoversLiveBoundariesAndTombstones() async throws {
        let db = try testDatabase()
        let cutoff = try iso("2026-10-04T00:00:00Z")
        let after = try iso("2026-10-05T00:00:00Z")
        let before = try iso("2026-10-03T23:59:59Z")
        let patientID = try seedPatient(db, at: cutoff)

        let exactAppt = try seedAppointment(
            db, patientID, start: iso("2026-10-03T23:30:00Z"), duration: 30)
        let oldAppt = try seedAppointment(
            db, patientID, start: iso("2026-10-03T23:29:00Z"), duration: 30)
        let straddleBlock = try seedBlock(db, start: iso("2026-10-03T23:45:00Z"), duration: 30)
        let oldBlock = try seedBlock(db, start: iso("2026-10-03T23:00:00Z"), duration: 59)

        #expect(
            try await db.isEligibleForCalendarRecovery(
                .appointment(exactAppt), eventStart: nil, cutoff: cutoff))
        #expect(
            try await !db.isEligibleForCalendarRecovery(
                .appointment(oldAppt), eventStart: after, cutoff: cutoff))
        #expect(
            try await db.isEligibleForCalendarRecovery(
                .unavailableTime(straddleBlock), eventStart: nil, cutoff: cutoff))
        #expect(
            try await !db.isEligibleForCalendarRecovery(
                .unavailableTime(oldBlock), eventStart: after, cutoff: cutoff))

        #expect(
            try await db.isEligibleForCalendarRecovery(
                .appointment(UUID()), eventStart: cutoff, cutoff: cutoff))
        #expect(
            try await db.isEligibleForCalendarRecovery(
                .unavailableTime(UUID()), eventStart: after, cutoff: cutoff))
        #expect(
            try await !db.isEligibleForCalendarRecovery(
                .appointment(UUID()), eventStart: before, cutoff: cutoff))
        #expect(
            try await !db.isEligibleForCalendarRecovery(
                .unavailableTime(UUID()), eventStart: nil, cutoff: cutoff))
    }

    @Test func fetchPendingWorkOrdersAppointmentsBeforeBlocksWithCutoffs() async throws {
        let db = try testDatabase()
        let t1 = try iso("2026-10-05T08:00:00Z")
        let t2 = try iso("2026-10-05T09:00:00Z")
        let cutoff = try iso("2026-10-04T00:00:00Z")
        let patientID = try seedPatient(db, at: t1)

        let id1 = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let id2 = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let id3 = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let syncedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
        let block2 = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000005"))

        _ = try seedAppointment(db, patientID, id: id3, start: t2, duration: 30)
        _ = try seedAppointment(db, patientID, id: id2, start: t1, duration: 30)
        _ = try seedAppointment(db, patientID, id: id1, start: t1, duration: 30)
        _ = try seedAppointment(db, patientID, id: syncedID, start: t1, duration: 30)
        _ = try seedBlock(db, id: id1, start: t1, duration: 30)
        _ = try seedBlock(db, id: block2, start: t2, duration: 30)

        try await db.write { db in
            try updateOutbox(.appointment(id1), eventID: "appt-shared", updatedAt: t1, in: db)
            try updateOutbox(.appointment(id2), updatedAt: t1, in: db)
            try updateOutbox(.appointment(id3), updatedAt: t2, in: db)
            try updateOutbox(.appointment(syncedID), needsSync: false, in: db)
            try updateOutbox(.unavailableTime(id1), eventID: "block-shared", updatedAt: t1, in: db)
            try updateOutbox(.unavailableTime(block2), updatedAt: t2, in: db)
        }

        let initial = try await db.fetchPendingCalendarSyncWork()
        #expect(
            initial.map(\.source) == [
                .appointment(id1), .appointment(id2), .appointment(id3),
                .unavailableTime(id1), .unavailableTime(block2),
            ])
        #expect(initial.allSatisfy { $0.recoveryCutoff == nil })
        #expect(initial.first?.eventIdentifier == "appt-shared")
        #expect(
            initial.first { $0.source == .unavailableTime(id1) }?.eventIdentifier == "block-shared")

        try db.prepareCalendarRecovery(cutoff: cutoff)
        let recovered = try await db.fetchPendingCalendarSyncWork()
        #expect(
            recovered.map(\.source) == [
                .appointment(id1), .appointment(id2), .appointment(id3), .appointment(syncedID),
                .unavailableTime(id1), .unavailableTime(block2),
            ])
        #expect(recovered.allSatisfy { $0.recoveryCutoff == cutoff })
    }

    @Test func saveLinkChecksRevisionAndClearsRecoveryOnlyWhenSynced() async throws {
        let db = try testDatabase()
        let cutoff = try iso("2026-10-04T00:00:00Z")
        let start = try iso("2026-10-05T10:00:00Z")
        let newerAt = try iso("2026-10-05T10:02:00Z")
        let savedAt = try iso("2026-10-05T10:05:00Z")
        let patientID = try seedPatient(db, at: start)

        let currentAppt = try seedAppointment(db, patientID, start: start, duration: 30)
        let staleBlock = try seedBlock(db, start: start, duration: 60)
        try db.prepareCalendarRecovery(cutoff: cutoff)

        let pending = try await db.fetchPendingCalendarSyncWork()
        let currentWork = try #require(pending.first { $0.source == .appointment(currentAppt) })
        let staleWork = try #require(pending.first { $0.source == .unavailableTime(staleBlock) })

        // Advance the block outbox revision before saving the earlier result.
        try await db.write { db in
            try UnavailableTimeRecord.find(staleBlock).update {
                $0.label = #bind("Moved", as: String?.self)
                $0.updatedAt = newerAt
            }.execute(db)
            try updateOutbox(.unavailableTime(staleBlock), updatedAt: newerAt, in: db)
        }

        try await db.saveCalendarSyncLink(
            eventIdentifier: "appt-1", eventStart: start, for: currentWork, at: savedAt)
        try await db.saveCalendarSyncLink(
            eventIdentifier: "block-1", eventStart: start, for: staleWork, at: savedAt)

        try await db.read { db in
            let current = try #require(try appointmentOutbox(currentAppt, in: db))
            #expect(
                !current.needsSync && current.eventIdentifier == "appt-1"
                    && current.eventStart == start && current.updatedAt == savedAt)

            let stale = try #require(try blockOutbox(staleBlock, in: db))
            #expect(stale.needsSync && stale.revision == staleWork.revision + 1)
            #expect(
                stale.eventIdentifier == "block-1" && stale.eventStart == start
                    && stale.updatedAt == newerAt)
            #expect(try recoveryCount(in: db) == 1)
        }

        let remaining = try await db.fetchPendingCalendarSyncWork()
        #expect(remaining.map(\.source) == [.unavailableTime(staleBlock)])
        #expect(remaining.first?.eventIdentifier == "block-1")
        #expect(remaining.first?.recoveryCutoff == cutoff)
    }

    @Test func deleteWorkIfCurrentChecksRevisionAndHandlesMissingRecoveryTable() async throws {
        let db = try testDatabase()
        let cutoff = try iso("2026-10-04T00:00:00Z")
        let start = try iso("2026-10-05T10:00:00Z")
        let savedAt = try iso("2026-10-05T10:05:00Z")
        let patientID = try seedPatient(db, at: start)

        // Verify save and delete before clinicalCalendarRecovery exists.
        let plainAppt = try seedAppointment(db, patientID, start: start, duration: 30)
        let plainBlock = try seedBlock(db, start: start, duration: 30)
        let initial = try await db.fetchPendingCalendarSyncWork()
        try await db.saveCalendarSyncLink(
            eventIdentifier: "plain-1", eventStart: start,
            for: try #require(initial.first { $0.source == .appointment(plainAppt) }), at: savedAt
        )
        try await db.deleteCalendarSyncWorkIfCurrent(
            try #require(initial.first { $0.source == .unavailableTime(plainBlock) })
        )
        #expect(try await db.fetchPendingCalendarSyncWork().isEmpty)

        // Verify revision checks with clinicalCalendarRecovery present.
        let deletedAppt = try seedAppointment(db, patientID, start: start, duration: 30)
        let staleBlock = try seedBlock(db, start: start, duration: 60)
        try db.prepareCalendarRecovery(cutoff: cutoff)

        let pending = try await db.fetchPendingCalendarSyncWork()
        let currentWork = try #require(pending.first { $0.source == .appointment(deletedAppt) })
        let staleWork = try #require(pending.first { $0.source == .unavailableTime(staleBlock) })

        try await db.write { db in
            try UnavailableTimeRecord.find(staleBlock).update { $0.durationMinutes = 90 }.execute(
                db)
        }

        try await db.deleteCalendarSyncWorkIfCurrent(currentWork)
        try await db.deleteCalendarSyncWorkIfCurrent(staleWork)

        try await db.read { db in
            #expect(try appointmentOutbox(deletedAppt, in: db) == nil)
            let surviving = try #require(try blockOutbox(staleBlock, in: db))
            #expect(surviving.needsSync && surviving.revision == staleWork.revision + 1)
            #expect(try recoveryCount(in: db) == 2)  // plainAppt + staleBlock remain in recovery.
        }
    }

    private nonisolated func iso(_ value: String) throws -> Date {
        try Date(value, strategy: .iso8601)
    }

    private func seedPatient(_ db: DatabaseQueue, at date: Date) throws -> Patient.ID {
        let id = UUID()
        try db.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: id, name: "Aarav Mehta", phone: "+919820144532", dob: nil, gender: nil,
                    createdAt: date, updatedAt: date)
            }.execute(db)
        }
        return id
    }

    private func seedAppointment(
        _ db: DatabaseQueue, _ patientID: Patient.ID, id: Appointment.ID = UUID(), start: Date,
        duration: Int
    ) throws -> Appointment.ID {
        let record = try AppointmentRecord.persisted(
            id: id, patientID: patientID, start: start, durationMinutes: duration,
            status: .scheduled, createdAt: start, updatedAt: start
        )
        try db.write { try AppointmentRecord.insert { record }.execute($0) }
        return id
    }

    private func seedBlock(
        _ db: DatabaseQueue, id: UnavailableTime.ID = UUID(), start: Date, duration: Int
    ) throws -> UnavailableTime.ID {
        let record = UnavailableTimeRecord(
            id: id, label: "Blocked", start: start, durationMinutes: duration, createdAt: start,
            updatedAt: start)
        try db.write { try UnavailableTimeRecord.insert { record }.execute($0) }
        return id
    }

    private nonisolated func updateOutbox(
        _ source: CalendarSyncSource, eventID: String? = nil, eventStart: Date? = nil,
        needsSync: Bool? = nil, revision: Int? = nil, updatedAt: Date? = nil, in db: Database
    ) throws {
        let key =
            switch source {
            case .appointment: "appointmentID"
            case .unavailableTime: "unavailableTimeID"
            }
        var clauses: [String] = []
        var args: [any DatabaseValueConvertible?] = []
        if let eventID {
            clauses.append("eventIdentifier = ?")
            args.append(eventID)
        }
        if let eventStart {
            clauses.append("eventStart = ?")
            args.append(eventStart)
        }
        if let needsSync {
            clauses.append("needsSync = ?")
            args.append(needsSync ? 1 : 0)
        }
        if let revision {
            clauses.append("revision = ?")
            args.append(revision)
        }
        if let updatedAt {
            clauses.append("updatedAt = ?")
            args.append(updatedAt)
        }
        args.append(source.id.uuidString.lowercased())
        try db.execute(
            sql:
                "UPDATE \"\(source.outboxTableName)\" SET \(clauses.joined(separator: ", ")) WHERE \"\(key)\" = ?",
            arguments: StatementArguments(args)
        )
    }

    private nonisolated func insertOutbox(
        _ source: CalendarSyncSource, eventID: String?, eventStart: Date?,
        needsSync: Bool, revision: Int, at date: Date, in db: Database
    ) throws {
        let key =
            switch source {
            case .appointment: "appointmentID"
            case .unavailableTime: "unavailableTimeID"
            }
        try db.execute(
            sql:
                "INSERT INTO \"\(source.outboxTableName)\" (\"\(key)\", eventIdentifier, eventStart, needsSync, revision, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?)",
            arguments: [
                source.id.uuidString.lowercased(), eventID, eventStart, needsSync ? 1 : 0, revision,
                date, date,
            ]
        )
    }

    private nonisolated func appointmentOutbox(_ id: Appointment.ID, in db: Database) throws
        -> AppointmentCalendarSyncRecord?
    {
        try AppointmentCalendarSyncRecord.where { $0.appointmentID.eq(id) }.fetchOne(db)
    }

    private nonisolated func blockOutbox(_ id: UnavailableTime.ID, in db: Database) throws
        -> UnavailableTimeCalendarSyncRecord?
    {
        try UnavailableTimeCalendarSyncRecord.where { $0.unavailableTimeID.eq(id) }.fetchOne(db)
    }

    private nonisolated func recoveryCount(in db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT count(*) FROM clinicalCalendarRecovery") ?? 0
    }
}
