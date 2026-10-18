import EventKit
import Foundation
import GRDB
import OSLog
import SQLiteData

@MainActor
final class CalendarSyncCoordinator {
    @Dependency(\.calendar) private var calendar
    private let database: any DatabaseWriter
    private let calendarClient: CalendarClient
    private let contactClient: AppointmentContactClient

    private var observation: AnyDatabaseCancellable?
    private var isActivating = false
    private var isReady = false
    private var isDraining = false
    private var drainRequested = false
    private var eventChanges: Task<Void, Never>?

    init(
        database: any DatabaseWriter,
        calendarClient: CalendarClient,
        contactClient: AppointmentContactClient
    ) {
        self.database = database
        self.calendarClient = calendarClient
        self.contactClient = contactClient

        observation = DatabaseRegionObservation(
            tracking: Table("appointmentCalendarSync"), Table("unavailableTimeCalendarSync")
        )
        .start(
            in: database,
            onError: { error in
                calendarSyncLogger.error(
                    "Calendar sync database observation failed: \(String(describing: error), privacy: .public)"
                )
            },
            onChange: { [weak self] _ in
                Task { @MainActor in
                    await self?.requestDrain()
                }
            }
        )
        eventChanges = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                guard !Task.isCancelled else { return }
                await self?.activate()
            }
        }
    }

    deinit { eventChanges?.cancel() }

    func activate() async {
        guard !isActivating else { return }
        isActivating = true
        defer { isActivating = false }

        do {
            guard try await calendarClient.requestFullAccess() else {
                isReady = false
                calendarSyncLogger.notice("Full Calendar access was not granted")
                return
            }
        } catch {
            isReady = false
            calendarSyncLogger.error(
                "Requesting full Calendar access failed: \(String(describing: error), privacy: .public)"
            )
            return
        }

        guard await calendarClient.resolveTargetCalendar() else {
            isReady = false
            calendarSyncLogger.error(
                "No writable Calendar titled Bitehaus Debug is available"
            )
            return
        }

        isReady = true
        await requestDrain()
    }

    private func requestDrain() async {
        drainRequested = true
        guard isReady, !isDraining else { return }

        isDraining = true
        defer { isDraining = false }

        repeat {
            drainRequested = false
            await drainPendingRecords()
        } while drainRequested
    }

    private func drainPendingRecords() async {
        let records: [CalendarSyncWork]
        do {
            records = try await database.read { db in
                var recoveryCutoffs: [String: Date] = [:]
                if try db.tableExists("clinicalCalendarRecovery") {
                    for row in try Row.fetchAll(
                        db, sql: "SELECT source, sourceID, cutoff FROM clinicalCalendarRecovery")
                    {
                        let source: String = row["source"]
                        let id: String = row["sourceID"]
                        recoveryCutoffs[source + ":" + id] = row["cutoff"]
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
                            link: CalendarEventLink(
                                eventIdentifier: $0.eventIdentifier, eventStart: $0.eventStart,
                                recoveryCutoff: recoveryCutoffs[
                                    "appointmentCalendarSync:"
                                        + $0.appointmentID.uuidString.lowercased()]),
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
                            link: CalendarEventLink(
                                eventIdentifier: $0.eventIdentifier, eventStart: $0.eventStart,
                                recoveryCutoff: recoveryCutoffs[
                                    "unavailableTimeCalendarSync:"
                                        + $0.unavailableTimeID.uuidString.lowercased()]),
                            revision: $0.revision
                        )
                    }
                // Process appointment work first. Each source keeps its pending order.
                return appointments + blocks
            }
        } catch {
            calendarSyncLogger.error(
                "Loading Calendar work failed: \(String(describing: error), privacy: .public)")
            return
        }

        for (index, record) in records.enumerated() {
            if index.isMultiple(of: 64) { await Task.yield() }
            guard !Task.isCancelled else { return }
            do {
                try await process(record)
            } catch {
                calendarSyncLogger.error(
                    """
                    Calendar sync failed for source \
                    \(record.source.sortKey, privacy: .public): \
                    \(String(describing: error), privacy: .public)
                    """
                )
            }
        }
    }

    private func process(_ record: CalendarSyncWork) async throws {
        guard let markerURL = record.source.markerURL else {
            throw CalendarSyncError.invalidMarkerURL
        }
        let source: CalendarSourceState
        switch record.source {
        case .appointment(let id):
            source = try await sourceState(for: id)
        case .unavailableTime(let id):
            source = try await database.read { db in
                if let block = try UnavailableTimeRecord.find(id).fetchOne(db)?.unavailableTime {
                    return .replaceBlock(block)
                }
                return .remove(fallbackStart: nil)
            }
        }

        if let cutoff = record.link.recoveryCutoff {
            let table =
                switch record.source {
                case .appointment: "appointments"
                case .unavailableTime: "unavailableTimes"
                }
            let sourceIsEligible = try await database.read { db in
                try Int.fetchOne(
                    db,
                    sql:
                        "SELECT julianday(start) + durationMinutes / 1440.0 >= julianday(?) FROM \(table) WHERE id = ?",
                    arguments: [cutoff, record.source.uuid.uuidString.lowercased()])
            }
            let eligible =
                sourceIsEligible.map { $0 == 1 }
                ?? (record.link.eventStart.map { $0 >= cutoff } ?? false)
            if !eligible {
                // A newer edit can move a restored row outside the fixed recovery window.
                try await save(record.link, for: record)
                return
            }
        }

        switch source {
        case .remove(let fallbackStart):
            try await calendarClient.deleteEvent(record.link, markerURL, fallbackStart)
            try await deleteSyncRecordIfCurrent(record)
        case .replace(let details):
            let payload = try await eventPayload(for: details)
            let newLink = try await calendarClient.replaceEvent(record.link, payload)
            try await save(newLink, for: record)
        case .replaceBlock(let block):
            let payload = CalendarEventPayload(
                title: block.label.map { "Blocked: \($0)" } ?? "Blocked",
                start: block.start, end: block.end(using: calendar), notes: "", url: markerURL
            )
            let newLink = try await calendarClient.replaceEvent(record.link, payload)
            try await save(newLink, for: record)
        }
    }

    private func sourceState(
        for appointmentID: Appointment.ID
    ) async throws -> CalendarSourceState {
        try await database.read { db in
            guard let appointmentRecord = try AppointmentRecord.find(appointmentID).fetchOne(db)
            else {
                return .remove(fallbackStart: nil)
            }

            guard let status = Appointment.Status(storageValue: appointmentRecord.status) else {
                throw CalendarSyncError.invalidStoredStatus(appointmentRecord.status)
            }
            guard status != .cancelled else {
                return .remove(fallbackStart: appointmentRecord.start)
            }

            guard
                let patientRecord = try PatientRecord.find(appointmentRecord.patientID).fetchOne(
                    db
                )
            else {
                throw CalendarSyncError.missingPatient(appointmentRecord.patientID)
            }
            let patient = Patient(patientRecord)
            guard
                let appointment = appointmentRecord.appointment(patientName: patient.displayName)
            else {
                throw CalendarSyncError.invalidStoredStatus(appointmentRecord.status)
            }
            return .replace(AppointmentDetails(appointment: appointment, patient: patient))
        }
    }

    private func eventPayload(
        for details: AppointmentDetails
    ) async throws -> CalendarEventPayload {
        let phone = PhoneNumber.normalizedE164(details.patient.phone) ?? ""
        let contactName: String? =
            if phone.isEmpty {
                nil
            } else {
                await contactClient.nameForPhone(phone)
            }
        guard let url = ClinicalURL.appointment(details.appointment.id).url else {
            throw CalendarSyncError.invalidMarkerURL
        }

        return CalendarEventPayload(
            title: details.patient.displayName,
            start: details.appointment.start,
            end: details.appointment.end(using: calendar),
            notes: "Name: \(contactName ?? "")\nPhone: \(phone)",
            url: url
        )
    }

    private func save(_ link: CalendarEventLink, for record: CalendarSyncWork) async throws {
        let updatedAt = Date.now
        try await database.write { db in
            // SQL identifiers come only from the typed source. Values use database bindings.
            // A stale result must retain its new event link for the next pending revision.
            try db.execute(
                sql: """
                    UPDATE "\(record.source.table)"
                    SET eventIdentifier = ?, eventStart = ?,
                        needsSync = CASE WHEN revision = ? THEN 0 ELSE needsSync END,
                        updatedAt = CASE WHEN revision = ? THEN ? ELSE updatedAt END
                    WHERE "\(record.source.keyColumn)" = ?
                    """,
                arguments: [
                    link.eventIdentifier, link.eventStart, record.revision,
                    record.revision, updatedAt, record.source.uuid.uuidString.lowercased(),
                ]
            )
            if try db.tableExists("clinicalCalendarRecovery") {
                try db.execute(
                    sql: """
                        DELETE FROM clinicalCalendarRecovery WHERE source = ? AND sourceID = ?
                        AND EXISTS (SELECT 1 FROM \(record.source.table) WHERE \(record.source.keyColumn) = ? AND needsSync = 0)
                        """,
                    arguments: [
                        record.source.table, record.source.uuid.uuidString.lowercased(),
                        record.source.uuid.uuidString.lowercased(),
                    ])
            }
        }
    }

    private func deleteSyncRecordIfCurrent(_ record: CalendarSyncWork) async throws {
        try await database.write { db in
            try db.execute(
                sql:
                    "DELETE FROM \"\(record.source.table)\" WHERE \"\(record.source.keyColumn)\" = ? AND revision = ?",
                arguments: [record.source.uuid.uuidString.lowercased(), record.revision]
            )
            if db.changesCount > 0, try db.tableExists("clinicalCalendarRecovery") {
                try db.execute(
                    sql: "DELETE FROM clinicalCalendarRecovery WHERE source = ? AND sourceID = ?",
                    arguments: [record.source.table, record.source.uuid.uuidString.lowercased()])
            }
        }
    }
}

nonisolated private struct CalendarSyncWork: Sendable {
    let source: TimelineItem.ID
    let link: CalendarEventLink
    let revision: Int
}

nonisolated extension TimelineItem.ID {
    fileprivate var uuid: UUID {
        switch self {
        case .appointment(let id), .unavailableTime(let id): id
        }
    }

    fileprivate var table: String {
        switch self {
        case .appointment: "appointmentCalendarSync"
        case .unavailableTime: "unavailableTimeCalendarSync"
        }
    }

    fileprivate var keyColumn: String {
        switch self {
        case .appointment: "appointmentID"
        case .unavailableTime: "unavailableTimeID"
        }
    }

    fileprivate var markerURL: URL? {
        switch self {
        case .appointment(let id): ClinicalURL.appointment(id).url
        case .unavailableTime(let id): ClinicalURL.unavailableTime(id).url
        }
    }
}

nonisolated private enum CalendarSourceState: Sendable {
    case remove(fallbackStart: Date?)
    case replace(AppointmentDetails)
    case replaceBlock(UnavailableTime)
}

nonisolated private enum CalendarSyncError: Error, Sendable {
    case invalidStoredStatus(String)
    case missingPatient(Patient.ID)
    case invalidMarkerURL
}

nonisolated private let calendarSyncLogger = Logger(
    subsystem: "in.bitehaus.clinical",
    category: "CalendarSync"
)
