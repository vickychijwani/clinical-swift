import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

struct AppointmentBookingPatientQueryTests {
    @Test func mixesRecentVisitsAndPatientCreationWithoutDuplicateRows() throws {
        let database = try makeDatabase()
        let now = try date("2026-10-05T09:00:00Z")
        let patients = try [
            patient(1, name: "Zoya Shah", created: "2026-10-05T08:00:00Z"),
            patient(2, name: "Mary Shah", created: "2026-06-01T08:00:00Z"),
            patient(3, name: "Anjali Shah", created: "2026-10-03T08:00:00Z"),
            patient(4, name: "Aarav Mehta", created: "2026-05-01T08:00:00Z"),
        ]
        let appointments = try [
            appointment(1, patientID: patients[0].id, start: "2026-09-01T09:00:00Z"),
            appointment(2, patientID: patients[1].id, start: "2026-10-04T09:00:00Z"),
            appointment(3, patientID: patients[1].id, start: "2026-09-20T09:00:00Z",
                        status: .completed),
            appointment(4, patientID: patients[2].id, start: "2026-10-05T08:30:00Z",
                        status: .cancelled),
            appointment(5, patientID: patients[2].id, start: "2026-12-01T09:00:00Z"),
            appointment(6, patientID: patients[2].id, start: "2026-11-01T09:00:00Z",
                        status: .completed),
            appointment(7, patientID: patients[3].id, start: "2026-09-20T09:00:00Z",
                        status: .completed),
        ]
        try database.write { db in
            for patient in patients.reversed() {
                try PatientRecord.insert { patient }.execute(db)
            }
            for appointment in appointments {
                try AppointmentRecord.insert { appointment }.execute(db)
            }
        }

        let rows = try database.read { db in
            try appointmentBookingPatientRowsQuery(now: now).fetchAll(db)
        }
        #expect(rows.map(\.id) == patients.map(\.id))
        #expect(rows[2].nextAppointmentDate == appointments[4].start)

        let matches = rows.filter {
            PatientNameSearch.matches($0.details.patient.name, searchText: "sh")
        }
        #expect(matches.map(\.id) == Array(patients.prefix(3)).map(\.id))
        let listRows = try database.read { db in
            try patientListRowsQuery(now: now).fetchAll(db)
        }
        #expect(listRows.map(\.id) == [patients[3].id, patients[2].id, patients[1].id, patients[0].id])
    }

    @Test func equalRecencyUsesNameAndIDWithUnnamedPatientsLast() throws {
        let database = try makeDatabase()
        let now = try date("2026-10-05T09:00:00Z")
        let patients = try [
            patient(1, name: "Zoya", created: "2026-10-04T09:00:00Z"),
            patient(2, name: "anjali", created: "2026-10-04T09:00:00Z"),
            patient(3, name: "Anjali", created: "2026-10-04T09:00:00Z"),
            patient(4, name: nil, created: "2026-10-04T09:00:00Z"),
            patient(5, name: nil, created: "2026-10-04T09:00:00Z"),
        ]
        try database.write { db in
            for patient in patients.reversed() {
                try PatientRecord.insert { patient }.execute(db)
            }
        }
        let rows = try database.read { db in
            try appointmentBookingPatientRowsQuery(now: now).fetchAll(db)
        }
        #expect(rows.map(\.id) == [patients[1].id, patients[2].id, patients[0].id,
                                 patients[3].id, patients[4].id])
    }

    @Test func timeBoundaryAndUpcomingMetadataUseIndependentFilters() throws {
        let database = try makeDatabase()
        let now = try date("2026-10-05T09:00:00Z")
        let patients = try [
            patient(1, name: "Zoya", created: "2026-06-01T09:00:00Z"),
            patient(2, name: "Anjali", created: "2026-10-04T09:00:00Z"),
        ]
        let appointments = try [
            appointment(1, patientID: patients[0].id, start: "2026-10-05T09:00:00Z"),
            appointment(2, patientID: patients[1].id, start: "2026-10-05T09:00:01Z",
                        status: .completed),
            appointment(3, patientID: patients[1].id, start: "2026-10-05T09:00:02Z",
                        status: .cancelled),
            appointment(4, patientID: patients[1].id, start: "2026-10-07T09:00:00Z"),
            appointment(5, patientID: patients[1].id, start: "2026-10-06T09:00:00Z"),
        ]
        try database.write { db in
            for patient in patients { try PatientRecord.insert { patient }.execute(db) }
            for appointment in appointments {
                try AppointmentRecord.insert { appointment }.execute(db)
            }
        }
        let rows = try database.read { db in
            try appointmentBookingPatientRowsQuery(now: now).fetchAll(db)
        }
        #expect(rows.map(\.id) == patients.map(\.id))
        #expect(rows[0].nextAppointmentDate == now)
        #expect(rows[1].nextAppointmentDate == appointments[4].start)

        let refreshedRows = try database.read { db in
            try appointmentBookingPatientRowsQuery(now: appointments[1].start).fetchAll(db)
        }
        #expect(refreshedRows.map(\.id) == patients.reversed().map(\.id))
    }

    @MainActor
    @Test func observationUpdatesAfterPatientAndAppointmentWrites() async throws {
        let database = try makeDatabase()
        let now = try date("2026-10-05T09:00:00Z")
        let first = try patient(1, name: "Anjali", created: "2026-10-03T09:00:00Z")
        let second = try patient(2, name: "Zoya", created: "2026-06-01T09:00:00Z")
        let newest = try patient(3, name: "Mary", created: "2026-10-05T08:00:00Z")
        let visit = try appointment(1, patientID: second.id, start: "2026-10-05T08:30:00Z")
        try await database.write { db in
            try PatientRecord.insert { first }.execute(db)
            try PatientRecord.insert { second }.execute(db)
        }

        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            @FetchAll(appointmentBookingPatientRowsQuery(now: now))
            var rows: [PatientDetailsSelection]
            try await $rows.load()
            #expect(rows.map(\.id) == [first.id, second.id])

            try await database.write { db in
                try PatientRecord.insert { newest }.execute(db)
            }
            try await waitUntil { rows.map(\.id) == [newest.id, first.id, second.id] }

            try await database.write { db in
                try AppointmentRecord.insert { visit }.execute(db)
            }
            try await waitUntil { rows.map(\.id) == [second.id, newest.id, first.id] }

            let future = try date("2026-10-06T09:00:00Z")
            try await database.write { db in
                try AppointmentRecord.find(visit.id).update { $0.start = #bind(future) }.execute(db)
            }
            try await waitUntil {
                rows.map(\.id) == [newest.id, first.id, second.id]
                    && rows.last?.nextAppointmentDate == future
            }

            try await database.write { db in
                try AppointmentRecord.find(visit.id).update {
                    $0.start = #bind(visit.start)
                    $0.status = #bind(Appointment.Status.completed.rawValue)
                }.execute(db)
            }
            try await waitUntil { rows.map(\.id) == [second.id, newest.id, first.id] }

            try await database.write { db in
                try AppointmentRecord.find(visit.id).delete().execute(db)
            }
            try await waitUntil { rows.map(\.id) == [newest.id, first.id, second.id] }

            try await database.write { db in
                try AppointmentRecord.insert { visit }.execute(db)
            }
            try await waitUntil { rows.first?.id == second.id }
            try await database.write { db in
                try AppointmentRecord.find(visit.id).update {
                    $0.status = #bind(Appointment.Status.cancelled.rawValue)
                }.execute(db)
            }
            try await waitUntil { rows.map(\.id) == [newest.id, first.id, second.id] }

            try await database.write { db in
                try PatientRecord.find(newest.id).delete().execute(db)
            }
            try await waitUntil { rows.map(\.id) == [first.id, second.id] }
        }
    }

    private func makeDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: configuration)
        try migrateDatabase(database)
        return database
    }

    private func date(_ value: String) throws -> Date {
        try Date(value, strategy: .iso8601)
    }

    private func patient(_ number: Int, name: String?, created: String) throws -> PatientRecord {
        PatientRecord(
            id: try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(number)")),
            name: name, phone: "+919820144532", dob: nil, gender: nil,
            createdAt: try date(created), updatedAt: try date("2026-10-05T08:59:00Z")
        )
    }

    private func appointment(
        _ number: Int, patientID: UUID, start: String,
        status: Appointment.Status = .scheduled
    ) throws -> AppointmentRecord {
        try AppointmentRecord.persisted(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(number)")),
            patientID: patientID, start: date(start), durationMinutes: 30, status: status,
            createdAt: date("2026-10-05T08:58:00Z"), updatedAt: date("2026-10-05T08:59:00Z")
        )
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("The observed booking patients did not update.")
    }
}
