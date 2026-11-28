import ClinicalModels
import ClinicalPersistence
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import clinical_swift

struct WidgetScheduleRepositoryTests {
    @Test func filtersByEndTimeAndStatusAndPreservesStartOrder() throws {
        let database = try testDatabase()
        let now = try Date("2026-07-13T10:30:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Aarav Mehta", createdDate: now)
        let unknownPatient = Patient(name: nil, phone: "+919820144532", createdDate: now)

        let inProgress = try appointment(
            patientID: patient.id,
            start: "2026-07-13T09:45:00+05:30",
            duration: 60,
            status: .scheduled
        )
        let ended = try appointment(
            patientID: patient.id,
            start: "2026-07-13T09:00:00+05:30",
            duration: 60,
            status: .scheduled
        )
        let endsNow = try appointment(
            patientID: patient.id,
            start: "2026-07-13T10:00:00+05:30",
            duration: 30,
            status: .scheduled
        )
        let completedButStillRunning = try appointment(
            patientID: unknownPatient.id,
            start: "2026-07-13T10:15:00+05:30",
            duration: 60,
            status: .completed
        )
        let cancelled = try appointment(
            patientID: patient.id,
            start: "2026-07-13T11:00:00+05:30",
            duration: 60,
            status: .cancelled
        )
        let tomorrow = try appointment(
            patientID: patient.id,
            start: "2026-07-14T09:00:00+05:30",
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

        let snapshot = try WidgetScheduleRepository(databaseURL: URL(filePath: "/unused"))
            .snapshot(in: database, at: now)

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
        let now = try Date("2026-07-13T10:30:00+05:30", strategy: .iso8601)
        let start = try Date("2026-07-13T10:15:00+05:30", strategy: .iso8601)
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
                    date: ClinicDate.day(now),
                    isToday: true,
                    items: [.appointment(appointment)]
                )
            ]
        )

        #expect(
            snapshot.nextRefreshDate(using: ClinicDate.calendar)
                == appointment.end(using: ClinicDate.calendar))
    }

    @Test func daySnapshotIncludesEndedCompletedAndUnavailableItemsForRequestedDay() throws {
        let database = try testDatabase()
        let now = try Date("2026-07-13T18:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Aarav Mehta", createdDate: now)

        let endedMorning = try appointment(
            patientID: patient.id,
            start: "2026-07-13T09:30:00+05:30",
            duration: 30,
            status: .completed
        )
        let upcomingEvening = try appointment(
            patientID: patient.id,
            start: "2026-07-13T19:00:00+05:30",
            duration: 45,
            status: .scheduled
        )
        let cancelled = try appointment(
            patientID: patient.id,
            start: "2026-07-13T11:00:00+05:30",
            duration: 30,
            status: .cancelled
        )
        let nextDayAppointment = try appointment(
            patientID: patient.id,
            start: "2026-07-14T10:00:00+05:30",
            duration: 30,
            status: .scheduled
        )
        let blockStart = try Date("2026-07-13T16:30:00+05:30", strategy: .iso8601)
        let block = UnavailableTimeRecord(
            id: UUID(),
            label: "Lab review",
            start: blockStart,
            durationMinutes: 60,
            createdAt: blockStart,
            updatedAt: blockStart
        )

        try database.write { database in
            try PatientRecord.insert { PatientRecord(patient) }.execute(database)
            for record in [endedMorning, upcomingEvening, cancelled, nextDayAppointment] {
                try AppointmentRecord.insert { record }.execute(database)
            }
            try UnavailableTimeRecord.insert { block }.execute(database)
        }

        let repository = WidgetScheduleRepository(databaseURL: URL(filePath: "/unused"))
        let today = ScheduleDay(date: now, calendar: ClinicDate.calendar)
        let todaySnapshot = try repository.daySnapshot(in: database, for: today, at: now)

        #expect(todaySnapshot.day == today)
        #expect(todaySnapshot.isToday)
        #expect(!todaySnapshot.isSunday)
        #expect(
            todaySnapshot.items.map(\.id) == [
                .appointment(endedMorning.id),
                .unavailableTime(block.id),
                .appointment(upcomingEvening.id),
            ])

        let sunday = try #require(ScheduleDay(year: 2026, month: 7, day: 19))
        let sundaySnapshot = try repository.daySnapshot(in: database, for: sunday, at: now)
        #expect(sundaySnapshot.day == sunday)
        #expect(!sundaySnapshot.isToday)
        #expect(sundaySnapshot.isSunday)
        #expect(sundaySnapshot.items.isEmpty)
    }

    @Test func readsAppointmentsBeforeUnavailableTimeMigrationRuns() throws {
        let database = try DatabaseQueue(configuration: clinicalDatabaseConfiguration())
        try databaseMigrator().migrate(
            database,
            upTo: "Create appointment Calendar sync outbox"
        )
        let now = try Date("2026-07-13T10:30:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Aarav Mehta", createdDate: now)
        let upcoming = try appointment(
            patientID: patient.id,
            start: "2026-07-13T11:00:00+05:30",
            duration: 45,
            status: .scheduled
        )

        try database.write { db in
            try PatientRecord.insert { PatientRecord(patient) }.execute(db)
            try AppointmentRecord.insert { upcoming }.execute(db)
        }

        let repository = WidgetScheduleRepository(databaseURL: URL(filePath: "/unused"))
        let scheduleSnapshot = try repository.snapshot(in: database, at: now)
        #expect(scheduleSnapshot.sections[0].items.map(\.id) == [.appointment(upcoming.id)])

        let today = ScheduleDay(date: now, calendar: ClinicDate.calendar)
        let daySnapshot = try repository.daySnapshot(in: database, for: today, at: now)
        #expect(daySnapshot.items.map(\.id) == [.appointment(upcoming.id)])
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
}
