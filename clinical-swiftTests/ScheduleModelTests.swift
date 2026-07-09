import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct ScheduleModelTests {
    @Test func loadVisibleDaysCachesPreviousSelectedAndNextAppointments() async throws {
        let calendar = gregorianCalendar
        let database = try testDatabase()
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let previousDate = selectedDate.date(byAddingDays: -1, using: calendar)
        let nextDate = selectedDate.date(byAddingDays: 1, using: calendar)
        let outsideDate = selectedDate.date(byAddingDays: 2, using: calendar)
        let previousID = UUID()
        let selectedID = UUID()
        let nextID = UUID()
        let cancelledID = UUID()

        try seedPatientAndAppointments(
            database: database,
            appointments: [
                AppointmentSeed(
                    id: previousID, start: previousDate.setTime(10, 0, using: calendar)),
                AppointmentSeed(
                    id: selectedID, start: selectedDate.setTime(11, 0, using: calendar)),
                AppointmentSeed(id: nextID, start: nextDate.setTime(12, 0, using: calendar)),
                AppointmentSeed(
                    id: cancelledID,
                    start: selectedDate.setTime(13, 0, using: calendar),
                    status: .cancelled
                ),
                AppointmentSeed(id: UUID(), start: outsideDate.setTime(14, 0, using: calendar)),
            ]
        )

        try await withDependencies {
            $0.calendar = calendar
            $0.defaultDatabase = database
        } operation: {
            let model = ScheduleModel(selectedDate: selectedDate)
            model.selectedDate = selectedDate.startOfDay(using: calendar)

            try await model.loadVisibleDays(centeredOn: selectedDate)

            #expect(model.appointments(for: previousDate).map(\.id) == [previousID])
            #expect(model.appointments.map(\.id) == [selectedID])
            #expect(model.appointments(for: nextDate).map(\.id) == [nextID])
            #expect(model.appointments(for: outsideDate).isEmpty)
            #expect(!model.appointments(for: selectedDate).contains { $0.id == cancelledID })
        }
    }

    @Test func staleVisibleDayLoadDoesNotOverwriteCurrentCache() async throws {
        let calendar = gregorianCalendar
        let database = try testDatabase()
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let staleDate = selectedDate.date(byAddingDays: -7, using: calendar)
        let selectedID = UUID()
        let staleID = UUID()

        try seedPatientAndAppointments(
            database: database,
            appointments: [
                AppointmentSeed(
                    id: selectedID, start: selectedDate.setTime(11, 0, using: calendar)),
                AppointmentSeed(id: staleID, start: staleDate.setTime(11, 0, using: calendar)),
            ]
        )

        try await withDependencies {
            $0.calendar = calendar
            $0.defaultDatabase = database
        } operation: {
            let model = ScheduleModel(selectedDate: selectedDate)
            model.selectedDate = selectedDate.startOfDay(using: calendar)

            try await model.loadVisibleDays(centeredOn: selectedDate)
            try await model.loadVisibleDays(centeredOn: staleDate)

            #expect(model.appointments.map(\.id) == [selectedID])
            #expect(model.appointments(for: staleDate).isEmpty)
        }
    }

    @Test func addingOneDayCrossesSundaySaturdayBoundary() throws {
        let calendar = gregorianCalendar
        let sunday = try Date("2026-04-19T00:00:00Z", strategy: .iso8601)
        let saturday = try Date("2026-04-18T00:00:00Z", strategy: .iso8601)

        #expect(sunday.date(byAddingDays: -1, using: calendar) == saturday)
        #expect(saturday.date(byAddingDays: 1, using: calendar) == sunday)
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func seedPatientAndAppointments(
        database: DatabaseQueue,
        appointments: [AppointmentSeed]
    ) throws {
        let patientID = UUID()
        let createdAt = try Date("2026-04-01T00:00:00Z", strategy: .iso8601)

        try database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: patientID,
                    name: "Aarav Mehta",
                    phone: nil,
                    dob: nil,
                    gender: nil,
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
            }
            .execute(db)

            for appointment in appointments {
                let record = try AppointmentRecord.persisted(
                    id: appointment.id,
                    patientID: patientID,
                    start: appointment.start,
                    durationMinutes: 30,
                    status: appointment.status,
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
                try AppointmentRecord.insert { record }
                    .execute(db)
            }
        }
    }

    private func testDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: configuration)
        try migrateDatabase(database)
        return database
    }

    private struct AppointmentSeed {
        let id: Appointment.ID
        let start: Date
        var status: Appointment.Status = .scheduled
    }
}
