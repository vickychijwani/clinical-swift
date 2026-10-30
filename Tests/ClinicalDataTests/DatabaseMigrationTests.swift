import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

struct DatabaseMigrationTests {
    @Test func populatedEarlierSchemaUpgradesWithoutErasure() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "clinical.db").path(percentEncoded: false)
        let earlier = try DatabaseQueue(path: path, configuration: clinicalDatabaseConfiguration())
        let patientID = UUID()
        let appointmentID = UUID()
        let date = try Date("2026-10-01T09:00:00Z", strategy: .iso8601)
        try earlier.write { db in
            // Keep this released schema fixed. Building it with today's migrator would hide old SQL edits.
            try db.execute(sql: Self.earlierSchema)
            try #sql(
                """
                INSERT INTO patients VALUES
                (\(bind: patientID), 'Aarav Mehta', '+91 98201 44532', '1990-01-02 00:00:00.000', 'male',
                 \(bind: date), \(bind: date))
                """
            ).execute(db)
            try #sql(
                """
                INSERT INTO appointments VALUES
                (\(bind: appointmentID), \(bind: patientID), \(bind: date), 45, 'completed',
                 \(bind: date), \(bind: date))
                """
            ).execute(db)
        }
        let originalAppointments = try earlier.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM appointments")
        }
        try earlier.close()

        let database = try DatabaseQueue(path: path, configuration: clinicalDatabaseConfiguration())
        defer { try? database.close() }
        let migrator = databaseMigrator(allowDebugErasure: false)
        try migrator.migrate(database)
        try withDependencies {
            $0.date.now = date
        } operation: {
            try database.write { db in
                #expect(try migrator.appliedMigrations(db) == migrator.migrations)
                #expect(
                    try Row.fetchAll(db, sql: "SELECT * FROM appointments") == originalAppointments)
                let patient = try #require(try PatientRecord.find(patientID).fetchOne(db))
                #expect(patient.name == "Aarav Mehta")
                #expect(patient.phone == "+919820144532")
                #expect(patient.dob == (try Date("1990-01-02T00:00:00Z", strategy: .iso8601)))
                #expect(patient.gender == "male")
                #expect(patient.createdAt == date)
                #expect(patient.updatedAt == date)

                try AppointmentRecord.find(appointmentID).update { $0.durationMinutes = 60 }
                    .execute(db)
                let delivery = try #require(
                    try AppointmentCalendarSyncRecord.where { $0.appointmentID.eq(appointmentID) }
                        .fetchOne(db))
                #expect(delivery.needsSync)
                let charge = AccountEntry(
                    details: .charge(patientID: patientID, appointmentID: appointmentID),
                    amount: 500, entryDate: date, createdDate: date)
                try saveAccountEntries(AccountEntryBatch(inserts: [charge]), in: db)
                #expect(try currentPatientBalance(patientID: patientID, in: db) == 500)
            }
        }
        let upgraded = try database.read { db in
            try [
                "patients", "appointments", "accountEntries", "patientBalances",
                "appointmentCalendarSync",
            ].map {
                try Row.fetchAll(db, sql: "SELECT * FROM \($0)")
            }
        }
        try migrator.migrate(database)
        try database.read { db in
            let reopened = try [
                "patients", "appointments", "accountEntries", "patientBalances",
                "appointmentCalendarSync",
            ].map {
                try Row.fetchAll(db, sql: "SELECT * FROM \($0)")
            }
            #expect(reopened == upgraded)
        }
    }

    private nonisolated static let earlierSchema = """
        CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
        INSERT INTO grdb_migrations VALUES ('Create patient and appointment tables');
        INSERT INTO grdb_migrations VALUES ('Create appointment indexes');
        CREATE TABLE patients (
          id TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          name TEXT, phone TEXT, dob TEXT, gender TEXT,
          createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL
        ) STRICT;
        CREATE TABLE appointments (
          id TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          patientID TEXT NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
          start TEXT NOT NULL, durationMinutes INTEGER NOT NULL, status TEXT NOT NULL,
          createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL
        ) STRICT;
        CREATE INDEX idx_appointments_patientID ON appointments(patientID);
        CREATE INDEX idx_appointments_start ON appointments(start);
        """
}
