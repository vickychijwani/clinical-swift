import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

struct BookingPersistenceTests {
    @Test func bookingDraftRecordIsReturnedByScheduleQuery() throws {
        let database = try testDatabase()
        let calendar = Calendar.autoupdatingCurrent
        let patientID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000005"))
        let selectedDate = Date(timeIntervalSinceReferenceDate: 20_000).startOfDay(using: calendar)
        let patient = Patient(
            id: patientID,
            name: "Aarav Mehta",
            createdDate: selectedDate
        )
        let patientItem = PatientDetails(
            patient: patient,
            nextAppointmentDate: nil
        )
        let now = selectedDate.setTime(9, 0, using: calendar)
        let appointmentID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000006"))
        let record = try withDependencies {
            $0.calendar = calendar
        } operation: {
            let draft = AppointmentBookingDraft(
                selectedPatient: patientItem.patient,
                selectedDate: selectedDate,
                start: selectedDate.setTime(10, 30, using: calendar),
                durationMinutes: 45
            )
            return try draft.makeRecord(id: appointmentID, now: now)
        }

        try database.write { db in
            try PatientRecord.insert { PatientRecord(patient) }
                .execute(db)

            try AppointmentRecord.insert { record }
                .execute(db)
        }

        let rows = try database.read { db in
            try querySchedule(selectedDate: selectedDate).fetchAll(db)
        }
        let appointment = try #require(rows.first?.details?.appointment)

        #expect(rows.count == 1)
        #expect(appointment.id == appointmentID)
        #expect(appointment.patientName == "Aarav Mehta")
        #expect(appointment.start == selectedDate.setTime(10, 30, using: calendar))
        #expect(appointment.durationMinutes == 45)
        #expect(appointment.status == .scheduled)
    }

    private func testDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: configuration)
        try migrateDatabase(database)
        return database
    }

}
