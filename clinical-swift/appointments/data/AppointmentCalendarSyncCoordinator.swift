import Foundation
import GRDB
import OSLog
import SQLiteData

@MainActor
final class AppointmentCalendarSyncCoordinator {
    private let database: any DatabaseWriter
    private let calendarClient: AppointmentCalendarClient
    private let contactClient: AppointmentContactClient

    private var observation: AnyDatabaseCancellable?
    private var isActivating = false
    private var isReady = false
    private var isDraining = false
    private var drainRequested = false

    init(
        database: any DatabaseWriter,
        calendarClient: AppointmentCalendarClient,
        contactClient: AppointmentContactClient
    ) {
        self.database = database
        self.calendarClient = calendarClient
        self.contactClient = contactClient

        observation = DatabaseRegionObservation(
            tracking: Table("appointmentCalendarSync")
        )
        .start(
            in: database,
            onError: { error in
                appointmentCalendarSyncLogger.error(
                    "Calendar sync database observation failed: \(String(describing: error), privacy: .public)"
                )
            },
            onChange: { [weak self] _ in
                Task { @MainActor in
                    await self?.requestDrain()
                }
            }
        )
    }

    func activate() async {
        guard !isActivating else { return }
        isActivating = true
        defer { isActivating = false }

        do {
            guard try await calendarClient.requestFullAccess() else {
                isReady = false
                appointmentCalendarSyncLogger.notice("Full Calendar access was not granted")
                return
            }
        } catch {
            isReady = false
            appointmentCalendarSyncLogger.error(
                "Requesting full Calendar access failed: \(String(describing: error), privacy: .public)"
            )
            return
        }

        guard calendarClient.resolveTargetCalendar() else {
            isReady = false
            appointmentCalendarSyncLogger.error(
                "No writable Calendar titled Bitehaus is available"
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
        let records: [AppointmentCalendarSyncRecord]
        do {
            records = try await database.read { db in
                try AppointmentCalendarSyncRecord
                    .where { $0.needsSync.eq(true) }
                    .order { ($0.updatedAt.asc(), $0.appointmentID.asc()) }
                    .fetchAll(db)
            }
        } catch {
            appointmentCalendarSyncLogger.error(
                """
                Loading pending Calendar sync work failed: \
                \(String(describing: error), privacy: .public)
                """
            )
            return
        }

        for record in records {
            do {
                try await process(record)
            } catch {
                appointmentCalendarSyncLogger.error(
                    """
                    Calendar sync failed for appointment \
                    \(record.appointmentID.uuidString, privacy: .public): \
                    \(String(describing: error), privacy: .public)
                    """
                )
            }
        }
    }

    private func process(_ record: AppointmentCalendarSyncRecord) async throws {
        let source = try await sourceState(for: record.appointmentID)
        let existingLink = AppointmentCalendarEventLink(
            eventIdentifier: record.eventIdentifier,
            eventStart: record.eventStart
        )

        switch source {
        case .remove(let fallbackStart):
            try await calendarClient.deleteEvent(
                existingLink,
                record.appointmentID,
                fallbackStart
            )
            try await deleteSyncRecordIfCurrent(record)

        case .replace(let details):
            let payload = try await eventPayload(for: details)
            let newLink = try await calendarClient.replaceEvent(existingLink, payload)
            try await save(newLink, for: record)
        }
    }

    private func sourceState(
        for appointmentID: Appointment.ID
    ) async throws -> AppointmentCalendarSourceState {
        try await database.read { db in
            guard let appointmentRecord = try AppointmentRecord.find(appointmentID).fetchOne(db)
            else {
                return .remove(fallbackStart: nil)
            }

            guard let status = Appointment.Status(storageValue: appointmentRecord.status) else {
                throw AppointmentCalendarSyncError.invalidStoredStatus(appointmentRecord.status)
            }
            guard status != .cancelled else {
                return .remove(fallbackStart: appointmentRecord.start)
            }

            guard
                let patientRecord = try PatientRecord.find(appointmentRecord.patientID).fetchOne(
                    db
                )
            else {
                throw AppointmentCalendarSyncError.missingPatient(appointmentRecord.patientID)
            }
            let patient = Patient(patientRecord)
            guard
                let appointment = appointmentRecord.appointment(patientName: patient.displayName)
            else {
                throw AppointmentCalendarSyncError.invalidStoredStatus(appointmentRecord.status)
            }
            return .replace(AppointmentDetails(appointment: appointment, patient: patient))
        }
    }

    private func eventPayload(
        for details: AppointmentDetails
    ) async throws -> AppointmentCalendarEventPayload {
        let phone = PhoneNumber.normalizedE164(details.patient.phone) ?? ""
        let contactName: String? =
            if phone.isEmpty {
                nil
            } else {
                await contactClient.nameForPhone(phone)
            }
        guard let url = ClinicalURL.appointment(details.appointment.id).url else {
            throw AppointmentCalendarSyncError.invalidMarkerURL
        }

        return AppointmentCalendarEventPayload(
            appointmentID: details.appointment.id,
            title: details.patient.displayName,
            start: details.appointment.start,
            end: details.appointment.end,
            notes: "Name: \(contactName ?? "")\nPhone: \(phone)",
            url: url
        )
    }

    private func save(
        _ link: AppointmentCalendarEventLink,
        for processedRecord: AppointmentCalendarSyncRecord
    ) async throws {
        let eventIdentifier = link.eventIdentifier
        let eventStart = link.eventStart
        let appointmentID = processedRecord.appointmentID
        let processedRevision = processedRecord.revision
        let updatedAt = Date.now

        try await database.write { db in
            guard
                let current = try
                    (AppointmentCalendarSyncRecord
                    .where { $0.appointmentID.eq(appointmentID) }
                    .fetchOne(db))
            else {
                return
            }

            if current.revision == processedRevision {
                try AppointmentCalendarSyncRecord
                    .where { $0.appointmentID.eq(appointmentID) }
                    .update {
                        $0.eventIdentifier = eventIdentifier
                        $0.eventStart = eventStart
                        $0.needsSync = false
                        $0.updatedAt = updatedAt
                    }
                    .execute(db)
            } else {
                // A newer app/database change committed while EventKit was running. Preserve the
                // pending revision, but point its retry at the event that was just created.
                try AppointmentCalendarSyncRecord
                    .where { $0.appointmentID.eq(appointmentID) }
                    .update {
                        $0.eventIdentifier = eventIdentifier
                        $0.eventStart = eventStart
                    }
                    .execute(db)
            }
        }
    }

    private func deleteSyncRecordIfCurrent(
        _ processedRecord: AppointmentCalendarSyncRecord
    ) async throws {
        let appointmentID = processedRecord.appointmentID
        let processedRevision = processedRecord.revision
        try await database.write { db in
            try AppointmentCalendarSyncRecord
                .where { $0.appointmentID.eq(appointmentID) }
                .where { $0.revision.eq(processedRevision) }
                .delete()
                .execute(db)
        }
    }
}

nonisolated private enum AppointmentCalendarSourceState: Sendable {
    case remove(fallbackStart: Date?)
    case replace(AppointmentDetails)
}

nonisolated private enum AppointmentCalendarSyncError: Error, Sendable {
    case invalidStoredStatus(String)
    case missingPatient(Patient.ID)
    case invalidMarkerURL
}

nonisolated private let appointmentCalendarSyncLogger = Logger(
    subsystem: "in.bitehaus.clinical",
    category: "AppointmentCalendarSync"
)
