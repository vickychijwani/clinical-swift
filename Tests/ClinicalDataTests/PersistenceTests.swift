import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData
import Testing

struct PersistenceTests {
    @Test func patientRecordMappingNormalizesBlankFields() throws {
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 2_000)
        let patient = Patient(
            id: id,
            name: "   ",
            phone: "  +91 98201 44532  ",
            dob: createdAt,
            gender: .other,
            createdDate: createdAt
        )

        let record = PatientRecord(patient, now: updatedAt)
        let mappedPatient = Patient(record)

        #expect(record.name == nil)
        #expect(record.phone == "+919820144532")
        #expect(record.gender == "other")
        #expect(record.createdAt == createdAt)
        #expect(record.updatedAt == updatedAt)
        #expect(mappedPatient.id == id)
        #expect(mappedPatient.name == nil)
        #expect(mappedPatient.phone == "+919820144532")
        #expect(mappedPatient.gender == .other)
        #expect(mappedPatient.createdDate == createdAt)
    }

    @Test func genderStorageMappingIsStable() {
        #expect(Gender.female.storageValue == "female")
        #expect(Gender.male.storageValue == "male")
        #expect(Gender.other.storageValue == "other")
        #expect(Gender(storageValue: "other") == .other)
        #expect(Gender(storageValue: "unexpected") == nil)
    }

    @Test func appointmentStatusStorageMappingIsDeterministic() {
        #expect(Appointment.Status.scheduled.persistedValue == "scheduled")
        #expect(Appointment.Status.draft.persistedValue == nil)
        #expect(Appointment.Status(storageValue: "completed") == .completed)
        #expect(Appointment.Status(storageValue: "draft") == nil)
        #expect(Appointment.Status(storageValue: "unexpected") == nil)
    }

    @Test func migrationsCreateTables() throws {
        let database = try testDatabase()

        let tableCount = try database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT count(*)
                    FROM "sqlite_master"
                    WHERE "type" = 'table'
                      AND "name" IN ('patients', 'appointments')
                    """
            ) ?? 0
        }

        #expect(tableCount == 2)
    }

    @Test func patientRowsDeriveNextAppointmentDate() throws {
        let database = try testDatabase()
        let patientID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let past = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = Date(timeIntervalSinceReferenceDate: 2_000)
        let next = Date(timeIntervalSinceReferenceDate: 3_000)
        let later = Date(timeIntervalSinceReferenceDate: 4_000)

        try database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: patientID,
                    name: "Aarav Mehta",
                    phone: nil,
                    dob: nil,
                    gender: nil,
                    createdAt: past,
                    updatedAt: past
                )
            }
            .execute(db)

            for start in [past, later, next] {
                let record = try AppointmentRecord.persisted(
                    id: UUID(),
                    patientID: patientID,
                    start: start,
                    durationMinutes: 30,
                    status: .scheduled,
                    createdAt: start,
                    updatedAt: start
                )
                try AppointmentRecord.insert { record }
                    .execute(db)
            }
        }

        let rows = try database.read { db in
            try patientListRowsQuery(now: now).fetchAll(db)
        }
        let detailsRow = try database.read { db in
            try patientDetailsQuery(id: patientID, now: now).fetchOne(db)
        }

        #expect(rows.map(\.details.nextAppointmentDate) == [next])
        #expect(rows.map(\.details.patient.name) == ["Aarav Mehta"])
        #expect(detailsRow?.details == rows.first?.details)
    }

    @Test func scheduleRowsJoinAppointmentsToPatientDisplayNames() throws {
        let database = try testDatabase()
        let patientID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let appointmentID = UUID()
        let selectedDate = Date(timeIntervalSinceReferenceDate: 10_000).startOfDay()
        let appointmentTime = selectedDate.setTime(10, 30)
        let dob = Date(timeIntervalSinceReferenceDate: -300_000_000)

        try database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: patientID,
                    name: "Anjali Desai",
                    phone: "+91 98209 46617",
                    dob: dob,
                    gender: "female",
                    createdAt: selectedDate,
                    updatedAt: selectedDate
                )
            }
            .execute(db)

            let record = try AppointmentRecord.persisted(
                id: appointmentID,
                patientID: patientID,
                start: appointmentTime,
                durationMinutes: 45,
                status: .completed,
                createdAt: appointmentTime,
                updatedAt: appointmentTime
            )
            try AppointmentRecord.insert { record }
                .execute(db)
        }

        let rows = try database.read { db in
            try querySchedule(selectedDate: selectedDate).fetchAll(db)
        }
        let detailsRow = try database.read { db in
            try appointmentDetailsQuery(id: appointmentID).fetchOne(db)
        }
        let appointment = try #require(rows.first?.details?.appointment)
        let details = try #require(rows.first?.details)
        let currentDetails = try #require(detailsRow?.details)

        #expect(rows.count == 1)
        #expect(appointment.patientName == "Anjali Desai")
        #expect(appointment.start == appointmentTime)
        #expect(appointment.durationMinutes == 45)
        #expect(appointment.status == .completed)
        #expect(details.patient.id == patientID)
        #expect(details.patient.phone == "+919820946617")
        #expect(details.patient.dob == dob)
        #expect(details.patient.gender == .female)
        #expect(currentDetails.appointment.id == appointmentID)
        #expect(currentDetails.patient.id == patientID)
        #expect(currentDetails.patient.name == "Anjali Desai")
    }

    @Test func earliestVisibleAppointmentIncludesCompletedAndIgnoresCancelledRows() throws {
        let database = try testDatabase()
        let calendar = Calendar.autoupdatingCurrent
        let patientID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000007"))
        let otherPatientID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000008"))
        let cancelledID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000009"))
        let completedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
        let earliestScheduledID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let laterScheduledID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000012"))
        let otherPatientAppointmentID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000013")
        )
        let day = Date(timeIntervalSinceReferenceDate: 20_000).startOfDay(using: calendar)

        try database.write { db in
            for (id, name) in [
                (patientID, "Aarav Mehta"),
                (otherPatientID, "Anjali Desai"),
            ] {
                try PatientRecord.insert {
                    PatientRecord(
                        id: id,
                        name: name,
                        phone: nil,
                        dob: nil,
                        gender: nil,
                        createdAt: day,
                        updatedAt: day
                    )
                }
                .execute(db)
            }

            for fixture in [
                AppointmentSeed(
                    id: cancelledID,
                    patientID: patientID,
                    start: day.setTime(9, 0, using: calendar),
                    status: .cancelled
                ),
                AppointmentSeed(
                    id: completedID,
                    patientID: patientID,
                    start: day.setTime(9, 30, using: calendar),
                    status: .completed
                ),
                AppointmentSeed(
                    id: earliestScheduledID,
                    patientID: patientID,
                    start: day.setTime(10, 0, using: calendar),
                    status: .scheduled
                ),
                AppointmentSeed(
                    id: laterScheduledID,
                    patientID: patientID,
                    start: day.setTime(11, 0, using: calendar),
                    status: .scheduled
                ),
                AppointmentSeed(
                    id: otherPatientAppointmentID,
                    patientID: otherPatientID,
                    start: day.setTime(8, 0, using: calendar),
                    status: .scheduled
                ),
            ] {
                let record = try AppointmentRecord.persisted(
                    id: fixture.id,
                    patientID: fixture.patientID,
                    start: fixture.start,
                    durationMinutes: 30,
                    status: fixture.status,
                    createdAt: fixture.start,
                    updatedAt: fixture.start
                )
                try AppointmentRecord.insert { record }
                    .execute(db)
            }
        }

        let earliest = try database.read { db in
            try earliestVisibleAppointmentQuery(patientID: patientID).fetchOne(db)
        }

        #expect(earliest?.id == completedID)
    }

    @Test func deletingPatientCascadesAppointments() throws {
        let database = try testDatabase()
        let patientID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
        let appointmentID = UUID()
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        try database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: patientID,
                    name: "Dev Malhotra",
                    phone: nil,
                    dob: nil,
                    gender: nil,
                    createdAt: now,
                    updatedAt: now
                )
            }
            .execute(db)

            let record = try AppointmentRecord.persisted(
                id: appointmentID,
                patientID: patientID,
                start: now,
                durationMinutes: 30,
                status: .scheduled,
                createdAt: now,
                updatedAt: now
            )
            try AppointmentRecord.insert { record }
                .execute(db)

            try PatientRecord.find(patientID).delete()
                .execute(db)
        }

        let appointmentCount = try database.read { db in
            try AppointmentRecord.count().fetchOne(db) ?? 0
        }
        let deletedPatient = try database.read { db in
            try patientDetailsQuery(id: patientID, now: now).fetchOne(db)
        }
        let deletedAppointment = try database.read { db in
            try appointmentDetailsQuery(id: appointmentID).fetchOne(db)
        }

        #expect(appointmentCount == 0)
        #expect(deletedPatient == nil)
        #expect(deletedAppointment == nil)
    }

    private struct AppointmentSeed {
        let id: Appointment.ID
        let patientID: Patient.ID
        let start: Date
        let status: Appointment.Status
    }
}
