import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct AppointmentBookingModelTests {
    @Test func todayInitialPrefillStartsAtNextFiveMinuteBoundary() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let examples: [(now: Date, expectedStart: Date)] = [
            (
                try Date("2026-04-21T16:13:00Z", strategy: .iso8601),
                selectedDate.setTime(16, 15, using: calendar)
            ),
            (
                try Date("2026-04-21T16:01:00Z", strategy: .iso8601),
                selectedDate.setTime(16, 5, using: calendar)
            ),
            (
                try Date("2026-04-21T16:15:55Z", strategy: .iso8601),
                selectedDate.setTime(16, 15, using: calendar)
            ),
            (
                try Date("2026-04-21T16:16:00Z", strategy: .iso8601),
                selectedDate.setTime(16, 20, using: calendar)
            ),
        ]

        for example in examples {
            try withDependencies {
                $0.calendar = calendar
                $0.date.now = example.now
            } operation: {
                let session = try bookingSession(date: selectedDate)
                #expect(session.preview.start == example.expectedStart)
            }
        }
    }

    @Test func nonTodayInitialPrefillUsesPreferredDefaultRegardlessOfCurrentTime() throws {
        let calendar = gregorianCalendar
        let tomorrow = try Date("2026-04-22T00:00:00Z", strategy: .iso8601)
        let yesterday = try Date("2026-04-20T00:00:00Z", strategy: .iso8601)
        let now = try Date("2026-04-21T16:13:00Z", strategy: .iso8601)

        try withDependencies {
            $0.calendar = calendar
            $0.date.now = now
        } operation: {
            let tomorrowSession = try bookingSession(date: tomorrow)
            let yesterdaySession = try bookingSession(date: yesterday)
            #expect(tomorrowSession.preview.start == tomorrow.setTime(10, 0, using: calendar))
            #expect(yesterdaySession.preview.start == yesterday.setTime(10, 0, using: calendar))
        }
    }

    @Test func editingUpdatesMutableFieldsAndPreservesRecordIdentityAndStatus() async throws {
        let calendar = gregorianCalendar
        let database = try testDatabase()
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let originalPatient = Patient(name: "Aarav Mehta", createdDate: selectedDate)
        let newPatient = Patient(name: "Anjali Desai", createdDate: selectedDate)
        let appointmentID = UUID()
        let createdAt = selectedDate.setTime(8, 0, using: calendar)
        let updatedAt = selectedDate.setTime(9, 0, using: calendar)
        let originalStart = selectedDate.setTime(10, 0, using: calendar)
        let editedStart = selectedDate.setTime(17, 0, using: calendar)

        try await database.write { db in
            try PatientRecord.insert { PatientRecord(originalPatient) }.execute(db)
            try PatientRecord.insert { PatientRecord(newPatient) }.execute(db)
            let record = try AppointmentRecord.persisted(
                id: appointmentID,
                patientID: originalPatient.id,
                start: originalStart,
                durationMinutes: 30,
                status: .scheduled,
                createdAt: createdAt,
                updatedAt: createdAt
            )
            try AppointmentRecord.insert { record }
                .execute(db)
        }

        var savedDate: Date?
        let didSave = try await withDependencies {
            $0.calendar = calendar
            $0.date.now = updatedAt
            $0.defaultDatabase = database
        } operation: {
            let details = AppointmentDetails(
                appointment: Appointment(
                    id: appointmentID,
                    patientName: originalPatient.displayName,
                    start: originalStart,
                    durationMinutes: 30,
                    status: .scheduled
                ),
                patient: originalPatient
            )
            let session = try editingSession(details) { savedDate = $0 }
            guard case .appointment(let model) = session.editor else { return false }
            model.draft.selectedPatient = newPatient
            model.draft.selectStart(editedStart)
            model.draft.selectDuration(60)
            return await session.save()
        }

        let record = try await database.read { db in
            try AppointmentRecord.find(appointmentID).fetchOne(db)
        }

        #expect(didSave)
        #expect(savedDate == editedStart)
        #expect(record?.id == appointmentID)
        #expect(record?.patientID == newPatient.id)
        #expect(record?.start == editedStart)
        #expect(record?.durationMinutes == 60)
        #expect(record?.status == Appointment.Status.scheduled.rawValue)
        #expect(record?.createdAt == createdAt)
        #expect(record?.updatedAt == updatedAt)
    }

    @Test func editingMissingAppointmentFailsWithoutCallingSaveCallback() async throws {
        let calendar = gregorianCalendar
        let database = try testDatabase()
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let patient = Patient(name: "Aarav Mehta", createdDate: selectedDate)
        var didCallSave = false

        let result = try await withDependencies {
            $0.calendar = calendar
            $0.date.now = selectedDate
            $0.defaultDatabase = database
        } operation: {
            let details = AppointmentDetails(
                appointment: Appointment(
                    patientName: patient.displayName,
                    start: selectedDate.setTime(10, 0, using: calendar),
                    durationMinutes: 30,
                    status: .scheduled
                ),
                patient: patient
            )
            let session = try editingSession(details) { _ in didCallSave = true }
            return (await session.save(), session.errorMessage)
        }

        #expect(!result.0)
        #expect(result.1 == "This appointment can no longer be edited.")
        #expect(!didCallSave)
    }

    @Test func chargedAppointmentKeepsPatientAndReportsEditFailure() async throws {
        let database = try testDatabase()
        let calendar = gregorianCalendar
        let now = try Date("2026-10-24T09:00:00Z", strategy: .iso8601)
        let patient = Patient(name: "Aarav Mehta", createdDate: now)
        let other = Patient(name: "Anjali Desai", createdDate: now)
        let appointment = Appointment(
            patientName: patient.displayName,
            start: now.setTime(10, 0, using: calendar), durationMinutes: 30, status: .scheduled)
        try await withDependencies {
            $0.date.now = now
            $0.calendar = calendar
            $0.defaultDatabase = database
        } operation: {
            try await database.write { db in
                try PatientRecord.insert { PatientRecord(patient, now: now) }.execute(db)
                try PatientRecord.insert { PatientRecord(other, now: now) }.execute(db)
                let record = try AppointmentRecord.persisted(
                    id: appointment.id, patientID: patient.id,
                    start: appointment.start, durationMinutes: 30, status: .scheduled,
                    createdAt: now, updatedAt: now)
                try AppointmentRecord.insert { record }.execute(db)
                let charge = AccountEntry(
                    details: .charge(patientID: patient.id, appointmentID: appointment.id),
                    amount: 500, entryDate: now, createdDate: now)
                try saveAccountEntries(AccountEntryBatch(inserts: [charge]), in: db)
            }
            var didSave = false
            let session = try editingSession(
                AppointmentDetails(appointment: appointment, patient: patient)
            ) { _ in didSave = true }
            guard case .appointment(let model) = session.editor else { return }
            model.draft.selectedPatient = other
            #expect(await session.save() == false)
            #expect(
                session.errorMessage
                    == "This appointment has charges. Remove its linked charges before changing the patient."
            )
            #expect(!didSave)
            let saved = try await database.read {
                try AppointmentRecord.find(appointment.id).fetchOne($0)
            }
            #expect(saved?.patientID == patient.id)
            // A charge must not prevent a schedule edit for the same patient.
            model.draft.selectedPatient = patient
            model.draft.selectStart(now.setTime(11, 0, using: calendar))
            #expect(await session.save())
            #expect(didSave)
        }
    }

    private func bookingSession(date: Date) throws -> ScheduleEditorSession {
        try #require(
            ScheduleEditorSession(
                request: .scheduleCreation(ScheduleCreationRequest()), selectedDate: date,
                appointments: [], onFinished: { _ in }))
    }

    private func editingSession(
        _ details: AppointmentDetails, onFinished: @escaping (Date) -> Void
    ) throws -> ScheduleEditorSession {
        try #require(
            ScheduleEditorSession(
                request: .appointmentEdit(AppointmentEditRequest(details: details)),
                selectedDate: details.appointment.start, appointments: [], onFinished: onFinished))
    }
    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func testDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: configuration)
        try migrateDatabase(database)
        return database
    }
}
