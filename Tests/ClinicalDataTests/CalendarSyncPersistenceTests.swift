import ClinicalModels
import ClinicalPersistence
import Foundation
import GRDB
import SQLiteData
import Testing

struct CalendarSyncPersistenceTests {
    @Test func prepareCalendarRecoveryEnforcesCutoffWindowTombstonesAndUnlinkedRecords()
        async throws
    {
        let database = try testDatabase()
        let cutoff = try Date("2026-10-04T00:00:00Z", strategy: .iso8601)
        let patientID = try insertPatient(into: database, at: cutoff)

        let boundaryAppointmentID = try insertAppointment(
            into: database,
            patientID: patientID,
            start: try Date("2026-10-03T23:30:00Z", strategy: .iso8601),
            durationMinutes: 30
        )
        let beforeCutoffAppointmentID = try insertAppointment(
            into: database,
            patientID: patientID,
            start: try Date("2026-10-03T23:29:00Z", strategy: .iso8601),
            durationMinutes: 30
        )
        let unlinkedAppointmentID = try insertAppointment(
            into: database,
            patientID: patientID,
            start: try Date("2026-10-05T10:00:00Z", strategy: .iso8601),
            durationMinutes: 30
        )
        let recentTombstoneID = UUID()
        let oldTombstoneID = UUID()
        let nilStartTombstoneID = UUID()

        let boundaryBlockID = try insertUnavailableTime(
            into: database,
            start: try Date("2026-10-03T23:45:00Z", strategy: .iso8601),
            durationMinutes: 30
        )
        let beforeCutoffBlockID = try insertUnavailableTime(
            into: database,
            start: try Date("2026-10-03T23:00:00Z", strategy: .iso8601),
            durationMinutes: 59
        )
        let unlinkedBlockID = try insertUnavailableTime(
            into: database,
            start: try Date("2026-10-06T09:00:00Z", strategy: .iso8601),
            durationMinutes: 60
        )
        let blockTombstoneID = UUID()

        try await database.write { db in
            try setAppointmentOutbox(
                boundaryAppointmentID, eventID: "appt-boundary",
                eventStart: try Date("2026-10-01T00:00:00Z", strategy: .iso8601),
                needsSync: false, revision: 4, in: db
            )
            try setAppointmentOutbox(
                beforeCutoffAppointmentID, eventID: "appt-old",
                eventStart: try Date("2026-10-10T00:00:00Z", strategy: .iso8601),
                needsSync: true, revision: 2, in: db
            )
            try AppointmentCalendarSyncRecord
                .where { $0.appointmentID.eq(unlinkedAppointmentID) }
                .delete()
                .execute(db)

            try insertAppointmentOutbox(
                recentTombstoneID, eventID: "tombstone-recent", eventStart: cutoff,
                needsSync: false, revision: 3, updatedAt: cutoff, in: db
            )
            try insertAppointmentOutbox(
                oldTombstoneID, eventID: "tombstone-old",
                eventStart: try Date("2026-10-03T23:59:59Z", strategy: .iso8601),
                needsSync: true, revision: 5, updatedAt: cutoff, in: db
            )
            try insertAppointmentOutbox(
                nilStartTombstoneID, eventID: nil, eventStart: nil,
                needsSync: true, revision: 1, updatedAt: cutoff, in: db
            )

            try setBlockOutbox(
                boundaryBlockID, eventID: "block-boundary",
                eventStart: try Date("2026-10-01T00:00:00Z", strategy: .iso8601),
                needsSync: false, revision: 2, in: db
            )
            try setBlockOutbox(
                beforeCutoffBlockID, eventID: "block-old",
                eventStart: try Date("2026-10-10T00:00:00Z", strategy: .iso8601),
                needsSync: true, revision: 7, in: db
            )
            try UnavailableTimeCalendarSyncRecord
                .where { $0.unavailableTimeID.eq(unlinkedBlockID) }
                .delete()
                .execute(db)
            try insertBlockOutbox(
                blockTombstoneID, eventID: "block-tombstone",
                eventStart: try Date("2026-10-04T01:00:00Z", strategy: .iso8601),
                needsSync: false, revision: 1, updatedAt: cutoff, in: db
            )
        }

        try database.prepareCalendarRecovery(cutoff: cutoff)

        let pending = try await database.fetchPendingCalendarSyncWork()
        #expect(
            Set(pending.map(\.source)) == [
                .appointment(boundaryAppointmentID),
                .appointment(recentTombstoneID),
                .unavailableTime(boundaryBlockID),
                .unavailableTime(blockTombstoneID),
            ]
        )
        #expect(pending.allSatisfy { $0.recoveryCutoff == cutoff })

        try await database.read { db in
            let boundaryRow = try #require(
                try AppointmentCalendarSyncRecord
                    .where { $0.appointmentID.eq(boundaryAppointmentID) }.fetchOne(db)
            )
            #expect(boundaryRow.needsSync)
            #expect(boundaryRow.revision == 5)
            #expect(boundaryRow.eventIdentifier == "appt-boundary")

            let oldRow = try #require(
                try AppointmentCalendarSyncRecord
                    .where { $0.appointmentID.eq(beforeCutoffAppointmentID) }.fetchOne(db)
            )
            #expect(!oldRow.needsSync)
            #expect(oldRow.revision == 3)
            #expect(oldRow.eventIdentifier == "appt-old")

            let oldTombstone = try #require(
                try AppointmentCalendarSyncRecord
                    .where { $0.appointmentID.eq(oldTombstoneID) }.fetchOne(db)
            )
            #expect(!oldTombstone.needsSync)
            #expect(oldTombstone.revision == 6)
            #expect(oldTombstone.eventIdentifier == "tombstone-old")

            let nilStartTombstone = try #require(
                try AppointmentCalendarSyncRecord
                    .where { $0.appointmentID.eq(nilStartTombstoneID) }.fetchOne(db)
            )
            #expect(!nilStartTombstone.needsSync)
            #expect(nilStartTombstone.revision == 2)

            #expect(
                try AppointmentCalendarSyncRecord
                    .where { $0.appointmentID.eq(unlinkedAppointmentID) }.fetchOne(db) == nil
            )
            #expect(
                try UnavailableTimeCalendarSyncRecord
                    .where { $0.unavailableTimeID.eq(unlinkedBlockID) }.fetchOne(db) == nil
            )

            let oldBlock = try #require(
                try UnavailableTimeCalendarSyncRecord
                    .where { $0.unavailableTimeID.eq(beforeCutoffBlockID) }.fetchOne(db)
            )
            #expect(!oldBlock.needsSync)
            #expect(oldBlock.revision == 8)

            #expect(try recoveryRowCount(in: db) == 4)
        }

        // Re-running preparation with a later cutoff clears earlier recovery rows.
        let laterCutoff = try Date("2026-10-04T00:30:00Z", strategy: .iso8601)
        try database.prepareCalendarRecovery(cutoff: laterCutoff)

        let laterPending = try await database.fetchPendingCalendarSyncWork()
        #expect(laterPending.map(\.source) == [.unavailableTime(blockTombstoneID)])
        #expect(laterPending.first?.recoveryCutoff == laterCutoff)
        #expect(try await database.read { try recoveryRowCount(in: $0) } == 1)
    }

    @Test func eligibilityCheckCoversLiveBoundariesAndTombstoneFallbacks() async throws {
        let database = try testDatabase()
        let cutoff = try Date("2026-10-04T00:00:00Z", strategy: .iso8601)
        let patientID = try insertPatient(into: database, at: cutoff)

        let exactEndAppointmentID = try insertAppointment(
            into: database,
            patientID: patientID,
            start: try Date("2026-10-03T23:30:00Z", strategy: .iso8601),
            durationMinutes: 30
        )
        let endedBeforeCutoffAppointmentID = try insertAppointment(
            into: database,
            patientID: patientID,
            start: try Date("2026-10-03T23:29:00Z", strategy: .iso8601),
            durationMinutes: 30
        )
        let straddlingBlockID = try insertUnavailableTime(
            into: database,
            start: try Date("2026-10-03T23:45:00Z", strategy: .iso8601),
            durationMinutes: 30
        )
        let endedBeforeCutoffBlockID = try insertUnavailableTime(
            into: database,
            start: try Date("2026-10-03T23:00:00Z", strategy: .iso8601),
            durationMinutes: 59
        )
        let missingAppointmentID = UUID()
        let missingBlockID = UUID()
        let afterCutoff = try Date("2026-10-05T00:00:00Z", strategy: .iso8601)
        let beforeCutoff = try Date("2026-10-03T23:59:59Z", strategy: .iso8601)

        #expect(
            try await database.isEligibleForCalendarRecovery(
                .appointment(exactEndAppointmentID), eventStart: nil, cutoff: cutoff
            )
        )
        #expect(
            try await !database.isEligibleForCalendarRecovery(
                .appointment(endedBeforeCutoffAppointmentID), eventStart: afterCutoff,
                cutoff: cutoff
            )
        )
        #expect(
            try await database.isEligibleForCalendarRecovery(
                .unavailableTime(straddlingBlockID), eventStart: nil, cutoff: cutoff
            )
        )
        #expect(
            try await !database.isEligibleForCalendarRecovery(
                .unavailableTime(endedBeforeCutoffBlockID), eventStart: afterCutoff, cutoff: cutoff
            )
        )

        #expect(
            try await database.isEligibleForCalendarRecovery(
                .appointment(missingAppointmentID), eventStart: cutoff, cutoff: cutoff
            )
        )
        #expect(
            try await database.isEligibleForCalendarRecovery(
                .unavailableTime(missingBlockID), eventStart: afterCutoff, cutoff: cutoff
            )
        )
        #expect(
            try await !database.isEligibleForCalendarRecovery(
                .appointment(missingAppointmentID), eventStart: beforeCutoff, cutoff: cutoff
            )
        )
        #expect(
            try await !database.isEligibleForCalendarRecovery(
                .unavailableTime(missingBlockID), eventStart: nil, cutoff: cutoff
            )
        )
    }

    @Test func fetchPendingWorkOrdersAppointmentsBeforeBlocksWithRecoveryCutoffs() async throws {
        let database = try testDatabase()
        let t1 = try Date("2026-10-05T08:00:00Z", strategy: .iso8601)
        let t2 = try Date("2026-10-05T09:00:00Z", strategy: .iso8601)
        let cutoff = try Date("2026-10-04T00:00:00Z", strategy: .iso8601)
        let patientID = try insertPatient(into: database, at: t1)

        let sharedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let tieBreakAppointmentID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )
        let laterAppointmentID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")
        )
        let syncedAppointmentID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000004")
        )
        let laterBlockID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000005")
        )

        _ = try insertAppointment(
            into: database, id: laterAppointmentID, patientID: patientID, start: t2,
            durationMinutes: 30
        )
        _ = try insertAppointment(
            into: database, id: tieBreakAppointmentID, patientID: patientID, start: t1,
            durationMinutes: 30
        )
        _ = try insertAppointment(
            into: database, id: sharedID, patientID: patientID, start: t1, durationMinutes: 30
        )
        _ = try insertAppointment(
            into: database, id: syncedAppointmentID, patientID: patientID, start: t1,
            durationMinutes: 30
        )
        _ = try insertUnavailableTime(into: database, id: sharedID, start: t1, durationMinutes: 30)
        _ = try insertUnavailableTime(
            into: database, id: laterBlockID, start: t2, durationMinutes: 30
        )

        try await database.write { db in
            try AppointmentCalendarSyncRecord.where { $0.appointmentID.eq(sharedID) }.update {
                $0.eventIdentifier = #bind("appt-shared", as: String?.self)
                $0.updatedAt = t1
            }.execute(db)
            try AppointmentCalendarSyncRecord
                .where { $0.appointmentID.eq(tieBreakAppointmentID) }.update {
                    $0.updatedAt = t1
                }.execute(db)
            try AppointmentCalendarSyncRecord
                .where { $0.appointmentID.eq(laterAppointmentID) }.update {
                    $0.updatedAt = t2
                }.execute(db)
            try AppointmentCalendarSyncRecord
                .where { $0.appointmentID.eq(syncedAppointmentID) }.update {
                    $0.needsSync = false
                }.execute(db)
            try UnavailableTimeCalendarSyncRecord
                .where { $0.unavailableTimeID.eq(sharedID) }.update {
                    $0.eventIdentifier = #bind("block-shared", as: String?.self)
                    $0.updatedAt = t1
                }.execute(db)
            try UnavailableTimeCalendarSyncRecord
                .where { $0.unavailableTimeID.eq(laterBlockID) }.update {
                    $0.updatedAt = t2
                }.execute(db)
        }

        let initialPending = try await database.fetchPendingCalendarSyncWork()
        #expect(
            initialPending.map(\.source) == [
                .appointment(sharedID),
                .appointment(tieBreakAppointmentID),
                .appointment(laterAppointmentID),
                .unavailableTime(sharedID),
                .unavailableTime(laterBlockID),
            ]
        )
        #expect(initialPending.allSatisfy { $0.recoveryCutoff == nil })
        #expect(initialPending.first?.eventIdentifier == "appt-shared")
        #expect(
            initialPending.first(where: { $0.source == .unavailableTime(sharedID) })?
                .eventIdentifier == "block-shared"
        )

        try database.prepareCalendarRecovery(cutoff: cutoff)
        let recoveryPending = try await database.fetchPendingCalendarSyncWork()
        #expect(
            recoveryPending.map(\.source) == [
                .appointment(sharedID),
                .appointment(tieBreakAppointmentID),
                .appointment(laterAppointmentID),
                .appointment(syncedAppointmentID),
                .unavailableTime(sharedID),
                .unavailableTime(laterBlockID),
            ]
        )
        #expect(recoveryPending.allSatisfy { $0.recoveryCutoff == cutoff })
    }

    @Test func saveLinkChecksRevisionAndClearsRecoveryOnlyWhenSynced() async throws {
        let database = try testDatabase()
        let cutoff = try Date("2026-10-04T00:00:00Z", strategy: .iso8601)
        let start = try Date("2026-10-05T10:00:00Z", strategy: .iso8601)
        let savedAt = try Date("2026-10-05T10:05:00Z", strategy: .iso8601)
        let patientID = try insertPatient(into: database, at: start)

        let currentAppointmentID = try insertAppointment(
            into: database, patientID: patientID, start: start, durationMinutes: 30
        )
        let staleBlockID = try insertUnavailableTime(
            into: database, start: start, durationMinutes: 60
        )
        try database.prepareCalendarRecovery(cutoff: cutoff)

        let pending = try await database.fetchPendingCalendarSyncWork()
        let currentWork = try #require(
            pending.first { $0.source == .appointment(currentAppointmentID) }
        )
        let staleWork = try #require(
            pending.first { $0.source == .unavailableTime(staleBlockID) }
        )

        // Advance the block outbox revision before saving the earlier result.
        let newerUpdatedAt = try Date("2026-10-05T10:02:00Z", strategy: .iso8601)
        try await database.write { db in
            try UnavailableTimeRecord.find(staleBlockID).update {
                $0.label = #bind("Moved", as: String?.self)
                $0.updatedAt = newerUpdatedAt
            }.execute(db)
            try UnavailableTimeCalendarSyncRecord
                .where { $0.unavailableTimeID.eq(staleBlockID) }.update {
                    $0.updatedAt = newerUpdatedAt
                }.execute(db)
        }

        try await database.saveCalendarSyncLink(
            eventIdentifier: "appt-event-1",
            eventStart: start,
            for: currentWork,
            at: savedAt
        )
        try await database.saveCalendarSyncLink(
            eventIdentifier: "block-event-1",
            eventStart: start,
            for: staleWork,
            at: savedAt
        )

        try await database.read { db in
            let currentRow = try #require(
                try AppointmentCalendarSyncRecord
                    .where { $0.appointmentID.eq(currentAppointmentID) }.fetchOne(db)
            )
            #expect(!currentRow.needsSync)
            #expect(currentRow.eventIdentifier == "appt-event-1")
            #expect(currentRow.eventStart == start)
            #expect(currentRow.updatedAt == savedAt)

            let staleRow = try #require(
                try UnavailableTimeCalendarSyncRecord
                    .where { $0.unavailableTimeID.eq(staleBlockID) }.fetchOne(db)
            )
            #expect(staleRow.needsSync)
            #expect(staleRow.revision == staleWork.revision + 1)
            #expect(staleRow.eventIdentifier == "block-event-1")
            #expect(staleRow.eventStart == start)
            #expect(staleRow.updatedAt == newerUpdatedAt)

            #expect(try recoveryRowCount(in: db) == 1)
        }

        let remaining = try await database.fetchPendingCalendarSyncWork()
        #expect(remaining.map(\.source) == [.unavailableTime(staleBlockID)])
        #expect(remaining.first?.eventIdentifier == "block-event-1")
        #expect(remaining.first?.recoveryCutoff == cutoff)
    }

    @Test func deleteWorkIfCurrentRemovesOutboxAndRecoveryOnlyForMatchingRevision() async throws {
        let database = try testDatabase()
        let cutoff = try Date("2026-10-04T00:00:00Z", strategy: .iso8601)
        let start = try Date("2026-10-05T10:00:00Z", strategy: .iso8601)
        let patientID = try insertPatient(into: database, at: start)

        let deletedAppointmentID = try insertAppointment(
            into: database, patientID: patientID, start: start, durationMinutes: 30
        )
        let recreatedBlockID = try insertUnavailableTime(
            into: database, start: start, durationMinutes: 60
        )
        try database.prepareCalendarRecovery(cutoff: cutoff)

        let pending = try await database.fetchPendingCalendarSyncWork()
        let currentWork = try #require(
            pending.first { $0.source == .appointment(deletedAppointmentID) }
        )
        let staleWork = try #require(
            pending.first { $0.source == .unavailableTime(recreatedBlockID) }
        )

        try await database.write { db in
            try UnavailableTimeRecord.find(recreatedBlockID).update {
                $0.durationMinutes = 90
                $0.updatedAt = start.addingTimeInterval(60)
            }.execute(db)
        }

        try await database.deleteCalendarSyncWorkIfCurrent(currentWork)
        try await database.deleteCalendarSyncWorkIfCurrent(staleWork)

        try await database.read { db in
            #expect(
                try AppointmentCalendarSyncRecord
                    .where { $0.appointmentID.eq(deletedAppointmentID) }.fetchOne(db) == nil
            )
            let survivingBlock = try #require(
                try UnavailableTimeCalendarSyncRecord
                    .where { $0.unavailableTimeID.eq(recreatedBlockID) }.fetchOne(db)
            )
            #expect(survivingBlock.needsSync)
            #expect(survivingBlock.revision == staleWork.revision + 1)
            #expect(try recoveryRowCount(in: db) == 1)
        }
    }

    @Test func saveAndDeleteWorkWhenRecoveryTableDoesNotExist() async throws {
        let database = try testDatabase()
        let start = try Date("2026-10-05T10:00:00Z", strategy: .iso8601)
        let savedAt = try Date("2026-10-05T10:05:00Z", strategy: .iso8601)
        let patientID = try insertPatient(into: database, at: start)

        let appointmentID = try insertAppointment(
            into: database, patientID: patientID, start: start, durationMinutes: 30
        )
        let blockID = try insertUnavailableTime(into: database, start: start, durationMinutes: 30)

        let pending = try await database.fetchPendingCalendarSyncWork()
        let appointmentWork = try #require(
            pending.first { $0.source == .appointment(appointmentID) }
        )
        let blockWork = try #require(
            pending.first { $0.source == .unavailableTime(blockID) }
        )

        try await database.saveCalendarSyncLink(
            eventIdentifier: "event-1", eventStart: start, for: appointmentWork, at: savedAt
        )
        try await database.deleteCalendarSyncWorkIfCurrent(blockWork)

        #expect(try await database.fetchPendingCalendarSyncWork().isEmpty)
        try await database.read { db in
            let saved = try #require(
                try AppointmentCalendarSyncRecord
                    .where { $0.appointmentID.eq(appointmentID) }.fetchOne(db)
            )
            #expect(!saved.needsSync)
            #expect(saved.eventIdentifier == "event-1")
            #expect(
                try UnavailableTimeCalendarSyncRecord
                    .where { $0.unavailableTimeID.eq(blockID) }.fetchOne(db) == nil
            )
        }
    }

    private func insertPatient(into database: DatabaseQueue, at date: Date) throws -> Patient.ID {
        let id = UUID()
        try database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: id,
                    name: "Aarav Mehta",
                    phone: "+919820144532",
                    dob: nil,
                    gender: nil,
                    createdAt: date,
                    updatedAt: date
                )
            }.execute(db)
        }
        return id
    }

    private func insertAppointment(
        into database: DatabaseQueue,
        id: Appointment.ID = UUID(),
        patientID: Patient.ID,
        start: Date,
        durationMinutes: Int
    ) throws -> Appointment.ID {
        let record = try AppointmentRecord.persisted(
            id: id,
            patientID: patientID,
            start: start,
            durationMinutes: durationMinutes,
            status: .scheduled,
            createdAt: start,
            updatedAt: start
        )
        try database.write { db in
            try AppointmentRecord.insert { record }.execute(db)
        }
        return id
    }

    private func insertUnavailableTime(
        into database: DatabaseQueue,
        id: UnavailableTime.ID = UUID(),
        start: Date,
        durationMinutes: Int
    ) throws -> UnavailableTime.ID {
        let record = UnavailableTimeRecord(
            id: id,
            label: "Blocked",
            start: start,
            durationMinutes: durationMinutes,
            createdAt: start,
            updatedAt: start
        )
        try database.write { db in
            try UnavailableTimeRecord.insert { record }.execute(db)
        }
        return id
    }

    private nonisolated func setAppointmentOutbox(
        _ id: Appointment.ID,
        eventID: String?,
        eventStart: Date?,
        needsSync: Bool,
        revision: Int,
        in db: Database
    ) throws {
        try AppointmentCalendarSyncRecord.where { $0.appointmentID.eq(id) }.update {
            $0.eventIdentifier = #bind(eventID, as: String?.self)
            $0.eventStart = #bind(eventStart, as: Date?.self)
            $0.needsSync = needsSync
            $0.revision = revision
        }.execute(db)
    }

    private nonisolated func insertAppointmentOutbox(
        _ id: Appointment.ID,
        eventID: String?,
        eventStart: Date?,
        needsSync: Bool,
        revision: Int,
        updatedAt: Date,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO "appointmentCalendarSync" (
                  "appointmentID", "eventIdentifier", "eventStart", "needsSync",
                  "revision", "createdAt", "updatedAt"
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id.uuidString.lowercased(), eventID, eventStart, needsSync ? 1 : 0,
                revision, updatedAt, updatedAt,
            ]
        )
    }

    private nonisolated func setBlockOutbox(
        _ id: UnavailableTime.ID,
        eventID: String?,
        eventStart: Date?,
        needsSync: Bool,
        revision: Int,
        in db: Database
    ) throws {
        try UnavailableTimeCalendarSyncRecord.where { $0.unavailableTimeID.eq(id) }.update {
            $0.eventIdentifier = #bind(eventID, as: String?.self)
            $0.eventStart = #bind(eventStart, as: Date?.self)
            $0.needsSync = needsSync
            $0.revision = revision
        }.execute(db)
    }

    private nonisolated func insertBlockOutbox(
        _ id: UnavailableTime.ID,
        eventID: String?,
        eventStart: Date?,
        needsSync: Bool,
        revision: Int,
        updatedAt: Date,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO "unavailableTimeCalendarSync" (
                  "unavailableTimeID", "eventIdentifier", "eventStart", "needsSync",
                  "revision", "createdAt", "updatedAt"
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id.uuidString.lowercased(), eventID, eventStart, needsSync ? 1 : 0,
                revision, updatedAt, updatedAt,
            ]
        )
    }

    private nonisolated func recoveryRowCount(in db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT count(*) FROM clinicalCalendarRecovery") ?? 0
    }
}
