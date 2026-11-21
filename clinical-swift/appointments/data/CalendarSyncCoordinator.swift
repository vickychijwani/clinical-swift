import ClinicalModels
import ClinicalPersistence
import Dependencies
import EventKit
import Foundation
import GRDB
import SQLiteData

@MainActor
final class CalendarSyncCoordinator {
    @Dependency(\.telemetry) private var telemetry
    private let database: any DatabaseWriter
    private let calendarClient: CalendarClient
    private let contactClient: AppointmentContactClient

    private var observation: AnyDatabaseCancellable?
    private var isActivating = false
    private var isReady = false
    private var drain: Task<Void, Never>?
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

        let telemetry = self.telemetry
        observation = calendarSyncOutboxObservation()
            .start(
                in: database,
                onError: { error in
                    telemetry.log(
                        .error,
                        category: .calendar,
                        name: "calendar_observation_failed",
                        message: "Calendar sync database observation failed",
                        error: error
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
                telemetry.log(
                    .warning,
                    category: .calendar,
                    name: "calendar_access_denied",
                    message: "Full Calendar access was not granted"
                )
                return
            }
        } catch {
            isReady = false
            telemetry.log(
                .error,
                category: .calendar,
                name: "calendar_access_request_failed",
                message: "Requesting full Calendar access failed",
                error: error
            )
            return
        }

        guard await calendarClient.resolveTargetCalendar() else {
            isReady = false
            telemetry.log(
                .error,
                category: .calendar,
                name: "calendar_target_missing",
                message: "No writable Calendar titled Bitehaus Debug is available"
            )
            return
        }

        isReady = true
        await requestDrain()
    }

    private func requestDrain() async {
        drainRequested = true
        guard isReady else { return }
        if let drain {
            await drain.value
            return
        }
        // Activation must also wait for a drain that a database change started.
        let task = Task {
            defer { drain = nil }
            repeat {
                drainRequested = false
                await drainPendingRecords()
            } while drainRequested
        }
        drain = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func drainPendingRecords() async {
        let records: [CalendarSyncWork]
        do {
            records = try await database.fetchPendingCalendarSyncWork()
        } catch {
            telemetry.log(
                .error,
                category: .calendar,
                name: "calendar_load_failed",
                message: "Loading Calendar work failed",
                error: error
            )
            return
        }

        guard !records.isEmpty else { return }
        let drainStart = ContinuousClock.now
        var syncedCount = 0
        var failureCount = 0

        for (index, record) in records.enumerated() {
            if index.isMultiple(of: 64) { await Task.yield() }
            guard !Task.isCancelled else { return }
            do {
                try await process(record)
                syncedCount += 1
            } catch {
                failureCount += 1
                telemetry.log(
                    .error,
                    category: .calendar,
                    name: "calendar_item_sync_failed",
                    message: "Calendar sync failed for source \(record.source.sortKey)",
                    error: error,
                    recordID: record.source.id.uuidString.lowercased(),
                    source: record.source.outboxTableName
                )
            }
        }

        let elapsed = drainStart.duration(to: ContinuousClock.now)
        let durationMS = Int(
            (Double(elapsed.components.seconds) * 1000.0
                + Double(elapsed.components.attoseconds) / 1e15).rounded())
        telemetry.event(
            category: .calendar,
            name: "calendar_sync_drained",
            durationMS: durationMS,
            count: syncedCount,
            status: failureCount > 0 ? "partial" : "ok"
        )
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

        if let cutoff = record.recoveryCutoff {
            let eligible = try await database.isEligibleForCalendarRecovery(
                record.source,
                eventStart: record.eventStart,
                cutoff: cutoff
            )
            if !eligible {
                // A newer edit can move a restored row outside the fixed recovery window.
                try await save(record.link, for: record)
                return
            }
        }

        switch source {
        case .remove(let fallbackStart):
            try await calendarClient.deleteEvent(record.link, markerURL, fallbackStart)
            try await database.deleteCalendarSyncWorkIfCurrent(record)
        case .replace(let details):
            let payload = try await eventPayload(for: details)
            let newLink = try await calendarClient.replaceEvent(record.link, payload)
            try await save(newLink, for: record)
        case .replaceBlock(let block):
            let payload = CalendarEventPayload(
                title: block.label.map { "Blocked: \($0)" } ?? "Blocked",
                start: block.start, end: block.end(using: ClinicDate.calendar), notes: "",
                url: markerURL
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
            end: details.appointment.end(using: ClinicDate.calendar),
            notes: "Name: \(contactName ?? "")\nPhone: \(phone)",
            url: url
        )
    }

    private func save(_ link: CalendarEventLink, for record: CalendarSyncWork) async throws {
        try await database.saveCalendarSyncLink(
            eventIdentifier: link.eventIdentifier,
            eventStart: link.eventStart,
            for: record,
            at: .now
        )
    }
}

nonisolated extension CalendarSyncWork {
    fileprivate var link: CalendarEventLink {
        CalendarEventLink(
            eventIdentifier: eventIdentifier,
            eventStart: eventStart,
            recoveryCutoff: recoveryCutoff
        )
    }
}

nonisolated extension CalendarSyncSource {
    fileprivate var sortKey: String {
        switch self {
        case .appointment(let id): "appointment-\(id.uuidString)"
        case .unavailableTime(let id): "unavailable-time-\(id.uuidString)"
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
