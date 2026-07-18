import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct AppointmentCalendarSyncCoordinatorTests {
    @Test func activationCreatesExactCalendarPayloadAndClearsPendingWork() async throws {
        let database = try testDatabase()
        let fixture = try insertFixture(into: database)
        let calendarRecorder = CalendarClientRecorder()
        let contactRecorder = ContactNameRecorder(name: "Aarav Mobile")
        let coordinator = AppointmentCalendarSyncCoordinator(
            database: database,
            calendarClient: calendarRecorder.client,
            contactClient: contactRecorder.client
        )

        await activate(coordinator)

        let replacement = try #require(calendarRecorder.replacements.first)
        #expect(replacement.link.eventIdentifier == nil)
        #expect(replacement.payload.appointmentID == fixture.appointmentID)
        #expect(replacement.payload.title == "Aarav Mehta")
        #expect(replacement.payload.start == fixture.start)
        #expect(replacement.payload.end == fixture.start.addingTimeInterval(30 * 60))
        #expect(replacement.payload.notes == "Name: Aarav Mobile\nPhone: +919820144532")
        #expect(
            replacement.payload.url.absoluteString
                == "clinical://appointments/\(fixture.appointmentID.uuidString.lowercased())"
        )
        #expect(contactRecorder.requestedPhones == ["+919820144532"])

        let fetchedSyncRecord = try fetchSyncRecord(fixture.appointmentID, from: database)
        let syncRecord = try #require(fetchedSyncRecord)
        #expect(!syncRecord.needsSync)
        #expect(syncRecord.eventIdentifier == "event-1")
        #expect(syncRecord.eventStart == fixture.start)
    }

    @Test func unavailableCalendarRetainsPendingWork() async throws {
        let database = try testDatabase()
        let fixture = try insertFixture(into: database)
        let calendarRecorder = CalendarClientRecorder()
        calendarRecorder.targetAvailable = false
        let coordinator = AppointmentCalendarSyncCoordinator(
            database: database,
            calendarClient: calendarRecorder.client,
            contactClient: ContactNameRecorder(name: nil).client
        )

        await activate(coordinator)

        #expect(calendarRecorder.replacements.isEmpty)
        #expect(calendarRecorder.resolveCount == 1)
        #expect(try fetchSyncRecord(fixture.appointmentID, from: database)?.needsSync == true)
    }

    @Test func missingContactAndPhoneProduceBlankNoteValues() async throws {
        let database = try testDatabase()
        let fixture = try insertFixture(into: database)
        try await database.write { db in
            try PatientRecord.find(fixture.patientID)
                .update {
                    $0.phone = #bind(nil, as: String?.self)
                    $0.updatedAt = fixture.start.addingTimeInterval(60)
                }
                .execute(db)
        }
        let calendarRecorder = CalendarClientRecorder()
        let contactRecorder = ContactNameRecorder(name: "Unused Contact")
        let coordinator = AppointmentCalendarSyncCoordinator(
            database: database,
            calendarClient: calendarRecorder.client,
            contactClient: contactRecorder.client
        )

        await activate(coordinator)

        #expect(calendarRecorder.replacements.first?.payload.notes == "Name: \nPhone: ")
        #expect(contactRecorder.requestedPhones.isEmpty)
    }

    @Test func failedReplacementRetriesOnNextActivation() async throws {
        let database = try testDatabase()
        let fixture = try insertFixture(into: database)
        let calendarRecorder = CalendarClientRecorder()
        calendarRecorder.replacementError = CalendarClientRecorderError.writeFailed
        let coordinator = AppointmentCalendarSyncCoordinator(
            database: database,
            calendarClient: calendarRecorder.client,
            contactClient: ContactNameRecorder(name: nil).client
        )

        await activate(coordinator)
        #expect(try fetchSyncRecord(fixture.appointmentID, from: database)?.needsSync == true)

        calendarRecorder.replacementError = nil
        await activate(coordinator)

        let fetchedSyncRecord = try fetchSyncRecord(fixture.appointmentID, from: database)
        let syncRecord = try #require(fetchedSyncRecord)
        #expect(calendarRecorder.replacements.count == 2)
        #expect(!syncRecord.needsSync)
        #expect(syncRecord.eventIdentifier == "event-2")
    }

    @Test func cancellationDeletesLinkedEventAndSyncRecord() async throws {
        let database = try testDatabase()
        let fixture = try insertFixture(into: database)
        try markSynced(fixture, eventIdentifier: "existing-event", in: database)
        try await database.write { db in
            try AppointmentRecord.find(fixture.appointmentID)
                .update {
                    $0.status = Appointment.Status.cancelled.rawValue
                    $0.updatedAt = fixture.start.addingTimeInterval(60)
                }
                .execute(db)
        }
        let calendarRecorder = CalendarClientRecorder()
        let coordinator = AppointmentCalendarSyncCoordinator(
            database: database,
            calendarClient: calendarRecorder.client,
            contactClient: ContactNameRecorder(name: nil).client
        )

        await activate(coordinator)

        let deletion = try #require(calendarRecorder.deletions.first)
        #expect(deletion.link.eventIdentifier == "existing-event")
        #expect(deletion.appointmentID == fixture.appointmentID)
        #expect(deletion.fallbackStart == fixture.start)
        #expect(try fetchSyncRecord(fixture.appointmentID, from: database) == nil)
    }

    @Test func patientCascadeDeletionStillDeletesLinkedEvent() async throws {
        let database = try testDatabase()
        let fixture = try insertFixture(into: database)
        try markSynced(fixture, eventIdentifier: "existing-event", in: database)
        try await database.write { db in
            try PatientRecord.find(fixture.patientID).delete().execute(db)
        }
        let calendarRecorder = CalendarClientRecorder()
        let coordinator = AppointmentCalendarSyncCoordinator(
            database: database,
            calendarClient: calendarRecorder.client,
            contactClient: ContactNameRecorder(name: nil).client
        )

        await activate(coordinator)

        let deletion = try #require(calendarRecorder.deletions.first)
        #expect(deletion.link.eventIdentifier == "existing-event")
        #expect(deletion.fallbackStart == nil)
        #expect(try fetchSyncRecord(fixture.appointmentID, from: database) == nil)
    }

    @Test func patientEditReplacesEventWithCurrentNamePhoneAndContact() async throws {
        let database = try testDatabase()
        let fixture = try insertFixture(into: database)
        try markSynced(fixture, eventIdentifier: "existing-event", in: database)
        try await database.write { db in
            try PatientRecord.find(fixture.patientID)
                .update {
                    $0.name = #bind("Aarav Updated")
                    $0.phone = #bind("+919876543210", as: String?.self)
                    $0.updatedAt = fixture.start.addingTimeInterval(60)
                }
                .execute(db)
        }
        let calendarRecorder = CalendarClientRecorder()
        let contactRecorder = ContactNameRecorder(name: "Current Contact")
        let coordinator = AppointmentCalendarSyncCoordinator(
            database: database,
            calendarClient: calendarRecorder.client,
            contactClient: contactRecorder.client
        )

        await activate(coordinator)

        let replacement = try #require(calendarRecorder.replacements.first)
        #expect(replacement.link.eventIdentifier == "existing-event")
        #expect(replacement.payload.title == "Aarav Updated")
        #expect(replacement.payload.notes == "Name: Current Contact\nPhone: +919876543210")
        #expect(contactRecorder.requestedPhones == ["+919876543210"])
    }

    private func testDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: configuration)
        try migrateDatabase(database)
        return database
    }

    private func activate(_ coordinator: AppointmentCalendarSyncCoordinator) async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        await withDependencies {
            $0.calendar = calendar
        } operation: {
            await coordinator.activate()
        }
    }

    private func insertFixture(
        into database: DatabaseQueue
    ) throws -> AppointmentCalendarCoordinatorFixture {
        let fixture = AppointmentCalendarCoordinatorFixture(
            patientID: UUID(),
            appointmentID: UUID(),
            start: Date(timeIntervalSinceReferenceDate: 900_000)
        )
        try database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: fixture.patientID,
                    name: "Aarav Mehta",
                    phone: "+919820144532",
                    dob: nil,
                    gender: nil,
                    createdAt: fixture.start,
                    updatedAt: fixture.start
                )
            }
            .execute(db)
            let appointment = try AppointmentRecord.persisted(
                id: fixture.appointmentID,
                patientID: fixture.patientID,
                start: fixture.start,
                durationMinutes: 30,
                status: .scheduled,
                createdAt: fixture.start,
                updatedAt: fixture.start
            )
            try AppointmentRecord.insert { appointment }.execute(db)
        }
        return fixture
    }

    private func markSynced(
        _ fixture: AppointmentCalendarCoordinatorFixture,
        eventIdentifier: String,
        in database: DatabaseQueue
    ) throws {
        try database.write { db in
            try AppointmentCalendarSyncRecord
                .where { $0.appointmentID.eq(fixture.appointmentID) }
                .update {
                    $0.eventIdentifier = #bind(eventIdentifier, as: String?.self)
                    $0.eventStart = #bind(fixture.start, as: Date?.self)
                    $0.needsSync = false
                }
                .execute(db)
        }
    }

    private func fetchSyncRecord(
        _ appointmentID: Appointment.ID,
        from database: DatabaseQueue
    ) throws -> AppointmentCalendarSyncRecord? {
        try database.read { db in
            try AppointmentCalendarSyncRecord
                .where { $0.appointmentID.eq(appointmentID) }
                .fetchOne(db)
        }
    }
}

@MainActor
private final class CalendarClientRecorder {
    struct Replacement {
        let link: AppointmentCalendarEventLink
        let payload: AppointmentCalendarEventPayload
    }

    struct Deletion {
        let link: AppointmentCalendarEventLink
        let appointmentID: Appointment.ID
        let fallbackStart: Date?
    }

    var accessGranted = true
    var targetAvailable = true
    var replacementError: Error?
    private(set) var resolveCount = 0
    private(set) var replacements: [Replacement] = []
    private(set) var deletions: [Deletion] = []

    var client: AppointmentCalendarClient {
        AppointmentCalendarClient(
            requestFullAccess: {
                self.accessGranted
            },
            resolveTargetCalendar: {
                self.resolveCount += 1
                return self.targetAvailable
            },
            replaceEvent: { link, payload in
                self.replacements.append(Replacement(link: link, payload: payload))
                if let replacementError = self.replacementError {
                    throw replacementError
                }
                return AppointmentCalendarEventLink(
                    eventIdentifier: "event-\(self.replacements.count)",
                    eventStart: payload.start
                )
            },
            deleteEvent: { link, appointmentID, fallbackStart in
                self.deletions.append(
                    Deletion(
                        link: link,
                        appointmentID: appointmentID,
                        fallbackStart: fallbackStart
                    )
                )
            }
        )
    }
}

@MainActor
private final class ContactNameRecorder {
    let name: String?
    private(set) var requestedPhones: [String] = []

    init(name: String?) {
        self.name = name
    }

    var client: AppointmentContactClient {
        AppointmentContactClient { phone in
            self.requestedPhones.append(phone)
            return self.name
        }
    }
}

private enum CalendarClientRecorderError: Error, Sendable {
    case writeFailed
}

private struct AppointmentCalendarCoordinatorFixture {
    let patientID: Patient.ID
    let appointmentID: Appointment.ID
    let start: Date
}
