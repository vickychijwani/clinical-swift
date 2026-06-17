import Foundation
import Dependencies
import SQLiteData
import Testing
@testable import clinical_swift

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
        #expect(record.phone == "+91 98201 44532")
        #expect(record.gender == "other")
        #expect(record.createdAt == createdAt)
        #expect(record.updatedAt == updatedAt)
        #expect(mappedPatient.id == id)
        #expect(mappedPatient.name == nil)
        #expect(mappedPatient.phone == "+91 98201 44532")
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
        #expect(Appointment.Status.scheduled.storageValue == "scheduled")
        #expect(Appointment.Status(storageValue: "completed") == .completed)
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

            for startTime in [past, later, next] {
                try AppointmentRecord.insert {
                    AppointmentRecord(
                        id: UUID(),
                        patientID: patientID,
                        startTime: startTime,
                        durationMinutes: 30,
                        status: Appointment.Status.scheduled.storageValue,
                        createdAt: startTime,
                        updatedAt: startTime
                    )
                }
                .execute(db)
            }
        }

        let rows = try database.read { db in
            try patientListRowsQuery(now: now).fetchAll(db)
        }

        #expect(rows.map(\.item.nextAppointmentDate) == [next])
        #expect(rows.map(\.item.patient.name) == ["Aarav Mehta"])
    }

    @Test func scheduleRowsJoinAppointmentsToPatientDisplayNames() throws {
        let database = try testDatabase()
        let patientID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let selectedDate = Date(timeIntervalSinceReferenceDate: 10_000).startOfDay()
        let appointmentTime = selectedDate.setTime(10, 30)

        try database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: patientID,
                    name: "Anjali Desai",
                    phone: nil,
                    dob: nil,
                    gender: "female",
                    createdAt: selectedDate,
                    updatedAt: selectedDate
                )
            }
            .execute(db)

            try AppointmentRecord.insert {
                AppointmentRecord(
                    id: UUID(),
                    patientID: patientID,
                    startTime: appointmentTime,
                    durationMinutes: 45,
                    status: Appointment.Status.completed.storageValue,
                    createdAt: appointmentTime,
                    updatedAt: appointmentTime
                )
            }
            .execute(db)
        }

        let rows = try database.read { db in
            try scheduleAppointmentsQuery(selectedDate: selectedDate).fetchAll(db)
        }
        let appointment = try #require(rows.first?.appointment)

        #expect(rows.count == 1)
        #expect(appointment.patientName == "Anjali Desai")
        #expect(appointment.startTime == appointmentTime)
        #expect(appointment.durationMinutes == 45)
        #expect(appointment.status == .completed)
    }

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
        let patientItem = PatientListItem(
            patient: patient,
            nextAppointmentDate: nil
        )
        let now = selectedDate.setTime(9, 0, using: calendar)
        let appointmentID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000006"))
        let record = try withDependencies {
            $0.calendar = calendar
        } operation: {
            let draft = AppointmentBookingDraft(
                selectedPatient: patientItem,
                selectedDate: selectedDate,
                startTime: selectedDate.setTime(10, 30, using: calendar),
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
            try scheduleAppointmentsQuery(selectedDate: selectedDate).fetchAll(db)
        }
        let appointment = try #require(rows.first?.appointment)

        #expect(rows.count == 1)
        #expect(appointment.id == appointmentID)
        #expect(appointment.patientName == "Aarav Mehta")
        #expect(appointment.startTime == selectedDate.setTime(10, 30, using: calendar))
        #expect(appointment.durationMinutes == 45)
        #expect(appointment.status == .scheduled)
    }

    @Test func deletingPatientCascadesAppointments() throws {
        let database = try testDatabase()
        let patientID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
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

            try AppointmentRecord.insert {
                AppointmentRecord(
                    id: UUID(),
                    patientID: patientID,
                    startTime: now,
                    durationMinutes: 30,
                    status: Appointment.Status.scheduled.storageValue,
                    createdAt: now,
                    updatedAt: now
                )
            }
            .execute(db)

            try PatientRecord.find(patientID).delete()
                .execute(db)
        }

        let appointmentCount = try database.read { db in
            try AppointmentRecord.count().fetchOne(db) ?? 0
        }

        #expect(appointmentCount == 0)
    }

    @Test func patientRecordInsertHonorsPatientValidationBoundary() throws {
        let database = try testDatabase()
        let validPatient = Patient(name: "Ishaan Verma")

        try validPatient.validate()
        try database.write { db in
            try PatientRecord.insert { PatientRecord(validPatient) }
                .execute(db)
        }

        let patientCount = try database.read { db in
            try PatientRecord.count().fetchOne(db) ?? 0
        }

        #expect(patientCount == 1)
        #expect(throws: Patient.ValidationError.missingNameAndPhone) {
            try Patient(name: nil, phone: nil).validate()
        }
    }

    private func testDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: configuration)
        try migrateDatabase(database)
        return database
    }
}
