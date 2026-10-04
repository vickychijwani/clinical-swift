import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import clinical_swift

struct WidgetScheduleRepositoryTests {
    @Test func filtersByEndTimeAndStatusAndPreservesStartOrder() throws {
        let database = try testDatabase()
        let calendar = utcCalendar()
        let now = try Date("2026-07-13T10:30:00Z", strategy: .iso8601)
        let patient = Patient(name: "Aarav Mehta", createdDate: now)
        let unknownPatient = Patient(name: nil, phone: "+919820144532", createdDate: now)

        let inProgress = try appointment(
            patientID: patient.id,
            start: "2026-07-13T09:45:00Z",
            duration: 60,
            status: .scheduled
        )
        let ended = try appointment(
            patientID: patient.id,
            start: "2026-07-13T09:00:00Z",
            duration: 60,
            status: .scheduled
        )
        let endsNow = try appointment(
            patientID: patient.id,
            start: "2026-07-13T10:00:00Z",
            duration: 30,
            status: .scheduled
        )
        let completedButStillRunning = try appointment(
            patientID: unknownPatient.id,
            start: "2026-07-13T10:15:00Z",
            duration: 60,
            status: .completed
        )
        let cancelled = try appointment(
            patientID: patient.id,
            start: "2026-07-13T11:00:00Z",
            duration: 60,
            status: .cancelled
        )
        let tomorrow = try appointment(
            patientID: patient.id,
            start: "2026-07-14T09:00:00Z",
            duration: 45,
            status: .scheduled
        )

        try database.write { database in
            try PatientRecord.insert { PatientRecord(patient) }.execute(database)
            try PatientRecord.insert { PatientRecord(unknownPatient) }.execute(database)
            for record in [
                ended, inProgress, endsNow, completedButStillRunning, cancelled, tomorrow,
            ] {
                try AppointmentRecord.insert { record }.execute(database)
            }
        }

        let snapshot = try withDependencies {
            $0.calendar = calendar
        } operation: {
            try WidgetScheduleRepository(databaseURL: URL(filePath: "/unused"))
                .snapshot(in: database, at: now)
        }

        #expect(snapshot.sections.count == 3)
        #expect(
            snapshot.sections[0].items.map(\.id) == [
                .appointment(inProgress.id), .appointment(completedButStillRunning.id),
            ])
        let unknownItem = try #require(snapshot.sections[0].items.last)
        guard case .appointment(let unknownAppointment) = unknownItem else {
            Issue.record("Expected an appointment for the unknown patient")
            return
        }
        #expect(unknownAppointment.patientName == Patient.unknownDisplayName)
        #expect(snapshot.sections[1].items.map(\.id) == [.appointment(tomorrow.id)])
        #expect(snapshot.sections[2].items.isEmpty)
    }

    @Test func nextRefreshIsTheEarlierOfAppointmentEndAndMidnight() throws {
        let calendar = utcCalendar()
        let now = try Date("2026-07-13T10:30:00Z", strategy: .iso8601)
        let start = try Date("2026-07-13T10:15:00Z", strategy: .iso8601)
        let appointment = Appointment(
            id: UUID(),
            patientName: "Aarav Mehta",
            start: start,
            durationMinutes: 60,
            status: .scheduled
        )
        let snapshot = WidgetScheduleSnapshot(
            generatedAt: now,
            sections: [
                WidgetScheduleSection(
                    date: calendar.startOfDay(for: now),
                    isToday: true,
                    items: [.appointment(appointment)]
                )
            ]
        )

        #expect(snapshot.nextRefreshDate(using: calendar) == appointment.end(using: calendar))
    }

    private func testDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: configuration)
        try migrateDatabase(database)
        return database
    }

    private func appointment(
        patientID: Patient.ID,
        start: String,
        duration: Int,
        status: Appointment.Status
    ) throws -> AppointmentRecord {
        let start = try Date(start, strategy: .iso8601)
        return try AppointmentRecord.persisted(
            id: UUID(),
            patientID: patientID,
            start: start,
            durationMinutes: duration,
            status: status,
            createdAt: start,
            updatedAt: start
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
}
