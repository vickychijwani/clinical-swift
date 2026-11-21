import ClinicalModels
import Foundation
import GRDB
import SQLiteData

/// Identifies which outbox table and source row a Calendar sync item belongs to.
public nonisolated enum CalendarSyncSource: Hashable, Sendable {
    case appointment(Appointment.ID)
    case unavailableTime(UnavailableTime.ID)

    public var id: UUID {
        switch self {
        case .appointment(let id), .unavailableTime(let id): id
        }
    }

    public var outboxTableName: String {
        outboxTable.tableName
    }

    fileprivate var outboxTable: CalendarSyncTable {
        switch self {
        case .appointment: .appointment
        case .unavailableTime: .unavailableTime
        }
    }

    fileprivate var storageID: String {
        id.uuidString.lowercased()
    }
}

/// Pending Calendar outbox work together with any fixed backup recovery cutoff.
public nonisolated struct CalendarSyncWork: Equatable, Sendable {
    public let source: CalendarSyncSource
    public let eventIdentifier: String?
    public let eventStart: Date?
    public let recoveryCutoff: Date?
    public let revision: Int

    public init(
        source: CalendarSyncSource,
        eventIdentifier: String?,
        eventStart: Date?,
        recoveryCutoff: Date? = nil,
        revision: Int
    ) {
        self.source = source
        self.eventIdentifier = eventIdentifier
        self.eventStart = eventStart
        self.recoveryCutoff = recoveryCutoff
        self.revision = revision
    }
}

public nonisolated func calendarSyncOutboxObservation() -> DatabaseRegionObservation {
    DatabaseRegionObservation(
        tracking: Table(CalendarSyncTable.appointment.tableName),
        Table(CalendarSyncTable.unavailableTime.tableName)
    )
}

extension DatabaseReader {
    public nonisolated func fetchPendingCalendarSyncWork() async throws -> [CalendarSyncWork] {
        try await read { db in
            var recoveryCutoffs: [String: Date] = [:]
            if try db.tableExists(calendarRecoveryTable) {
                for row in try Row.fetchAll(
                    db, sql: "SELECT source, sourceID, cutoff FROM \(calendarRecoveryTable)")
                {
                    let source: String = row["source"]
                    let id: String = row["sourceID"]
                    recoveryCutoffs[recoveryKey(table: source, id: id)] = row["cutoff"]
                }
            }
            let appointments =
                try AppointmentCalendarSyncRecord
                .where { $0.needsSync.eq(true) }
                .order { ($0.updatedAt.asc(), $0.appointmentID.asc()) }
                .fetchAll(db)
                .map {
                    CalendarSyncWork(
                        source: .appointment($0.appointmentID),
                        eventIdentifier: $0.eventIdentifier,
                        eventStart: $0.eventStart,
                        recoveryCutoff: recoveryCutoffs[
                            recoveryKey(
                                table: CalendarSyncTable.appointment.tableName,
                                id: $0.appointmentID.uuidString)
                        ],
                        revision: $0.revision
                    )
                }
            let blocks =
                try UnavailableTimeCalendarSyncRecord
                .where { $0.needsSync.eq(true) }
                .order { ($0.updatedAt.asc(), $0.unavailableTimeID.asc()) }
                .fetchAll(db)
                .map {
                    CalendarSyncWork(
                        source: .unavailableTime($0.unavailableTimeID),
                        eventIdentifier: $0.eventIdentifier,
                        eventStart: $0.eventStart,
                        recoveryCutoff: recoveryCutoffs[
                            recoveryKey(
                                table: CalendarSyncTable.unavailableTime.tableName,
                                id: $0.unavailableTimeID.uuidString)
                        ],
                        revision: $0.revision
                    )
                }
            // Process appointment work first. Each source keeps its pending order.
            return appointments + blocks
        }
    }

    public nonisolated func isEligibleForCalendarRecovery(
        _ source: CalendarSyncSource,
        eventStart: Date?,
        cutoff: Date
    ) async throws -> Bool {
        try await read { db in
            let sourceTable = source.outboxTable.sourceTableName
            if let sourceIsEligible = try Int.fetchOne(
                db,
                sql:
                    "SELECT \(recoverySourceEligibilitySQL()) FROM \"\(sourceTable)\" WHERE id = ?",
                arguments: [cutoff, source.storageID]
            ) {
                return sourceIsEligible == 1
            }
            guard let eventStart else { return false }
            return try Bool.fetchOne(
                db,
                sql: "SELECT julianday(?) >= julianday(?)",
                arguments: [eventStart, cutoff]
            ) ?? false
        }
    }
}

extension DatabaseWriter {
    public nonisolated func prepareCalendarRecovery(cutoff: Date) throws {
        try write { db in
            // This private table keeps the fixed recovery window across restarts and retries.
            try db.execute(
                sql:
                    "CREATE TABLE IF NOT EXISTS \(calendarRecoveryTable) (source TEXT NOT NULL, sourceID TEXT NOT NULL, cutoff TEXT NOT NULL, PRIMARY KEY (source, sourceID)) STRICT"
            )
            try db.execute(sql: "DELETE FROM \(calendarRecoveryTable)")
            for table in CalendarSyncTable.allCases {
                // Keep every historical link and tombstone, but stop excluded pending delivery.
                // Records without saved Calendar work must not enter Calendar during recovery.
                try db.execute(
                    sql: """
                        UPDATE "\(table.tableName)" SET needsSync = CASE
                          WHEN EXISTS (SELECT 1 FROM "\(table.sourceTableName)" s WHERE s.id = "\(table.tableName)"."\(table.keyColumn)"
                            AND \(recoverySourceEligibilitySQL(alias: "s"))) THEN 1
                          WHEN NOT EXISTS (SELECT 1 FROM "\(table.sourceTableName)" s WHERE s.id = "\(table.tableName)"."\(table.keyColumn)")
                            AND julianday(eventStart) >= julianday(?) THEN 1 ELSE 0 END,
                          revision = revision + 1
                        """,
                    arguments: [cutoff, cutoff]
                )
                try db.execute(
                    sql:
                        "INSERT INTO \(calendarRecoveryTable) SELECT ?, \"\(table.keyColumn)\", ? FROM \"\(table.tableName)\" WHERE needsSync = 1",
                    arguments: [table.tableName, cutoff]
                )
            }
        }
    }

    public nonisolated func saveCalendarSyncLink(
        eventIdentifier: String?,
        eventStart: Date?,
        for work: CalendarSyncWork,
        at updatedAt: Date
    ) async throws {
        try await write { db in
            let table = work.source.outboxTable
            let storageID = work.source.storageID
            // SQL identifiers come only from the typed source. Values use database bindings.
            // A stale result must retain its new event link for the next pending revision.
            try db.execute(
                sql: """
                    UPDATE "\(table.tableName)"
                    SET eventIdentifier = ?, eventStart = ?,
                        needsSync = CASE WHEN revision = ? THEN 0 ELSE needsSync END,
                        updatedAt = CASE WHEN revision = ? THEN ? ELSE updatedAt END
                    WHERE "\(table.keyColumn)" = ?
                    """,
                arguments: [
                    eventIdentifier, eventStart, work.revision,
                    work.revision, updatedAt, storageID,
                ]
            )
            if try db.tableExists(calendarRecoveryTable) {
                try db.execute(
                    sql: """
                        DELETE FROM \(calendarRecoveryTable) WHERE source = ? AND sourceID = ?
                        AND EXISTS (SELECT 1 FROM "\(table.tableName)" WHERE "\(table.keyColumn)" = ? AND needsSync = 0)
                        """,
                    arguments: [table.tableName, storageID, storageID]
                )
            }
        }
    }

    public nonisolated func deleteCalendarSyncWorkIfCurrent(_ work: CalendarSyncWork) async throws {
        try await write { db in
            let table = work.source.outboxTable
            let storageID = work.source.storageID
            try db.execute(
                sql:
                    "DELETE FROM \"\(table.tableName)\" WHERE \"\(table.keyColumn)\" = ? AND revision = ?",
                arguments: [storageID, work.revision]
            )
            if db.changesCount > 0, try db.tableExists(calendarRecoveryTable) {
                try db.execute(
                    sql: "DELETE FROM \(calendarRecoveryTable) WHERE source = ? AND sourceID = ?",
                    arguments: [table.tableName, storageID]
                )
            }
        }
    }
}

private nonisolated let calendarRecoveryTable = "clinicalCalendarRecovery"

private nonisolated enum CalendarSyncTable: CaseIterable {
    case appointment
    case unavailableTime

    var tableName: String {
        switch self {
        case .appointment: "appointmentCalendarSync"
        case .unavailableTime: "unavailableTimeCalendarSync"
        }
    }

    var keyColumn: String {
        switch self {
        case .appointment: "appointmentID"
        case .unavailableTime: "unavailableTimeID"
        }
    }

    var sourceTableName: String {
        switch self {
        case .appointment: "appointments"
        case .unavailableTime: "unavailableTimes"
        }
    }
}

private nonisolated func recoverySourceEligibilitySQL(alias: String? = nil) -> String {
    let prefix = alias.map { "\($0)." } ?? ""
    return "julianday(\(prefix)start) + \(prefix)durationMinutes / 1440.0 >= julianday(?)"
}

private nonisolated func recoveryKey(table: String, id: String) -> String {
    "\(table):\(id.lowercased())"
}
