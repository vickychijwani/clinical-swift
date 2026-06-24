import Foundation
import OSLog
import SQLiteData

func appDatabase(seedSamples: Bool = false) throws -> any DatabaseWriter {
    @Dependency(\.context) var context
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true

    #if DEBUG
    configuration.prepareDatabase { db in
        db.trace(options: .profile) {
            switch context {
            case .live:
                databaseLogger.debug("\($0.expandedDescription)")
            case .preview:
                print("\($0.expandedDescription)")
            case .test:
                break
            }
        }
    }
    #endif

    let database = try defaultDatabase(configuration: configuration)
    databaseLogger.debug("open '\(database.path)'")

    try migrateDatabase(database)

    #if DEBUG
    if seedSamples, context != .test {
        try database.seedSampleDataIfNeeded()
    }
    #endif

    return database
}

func migrateDatabase(_ database: any DatabaseWriter) throws {
    var migrator = DatabaseMigrator()
    #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("Create patient and appointment tables") { db in
        try #sql(
            """
            CREATE TABLE "patients" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "name" TEXT,
              "phone" TEXT,
              "dob" TEXT,
              "gender" TEXT,
              "createdAt" TEXT NOT NULL,
              "updatedAt" TEXT NOT NULL
            ) STRICT
            """
        )
        .execute(db)

        try #sql(
            """
            CREATE TABLE "appointments" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "patientID" TEXT NOT NULL REFERENCES "patients"("id") ON DELETE CASCADE,
              "start" TEXT NOT NULL,
              "durationMinutes" INTEGER NOT NULL,
              "status" TEXT NOT NULL,
              "createdAt" TEXT NOT NULL,
              "updatedAt" TEXT NOT NULL
            ) STRICT
            """
        )
        .execute(db)
    }

    migrator.registerMigration("Create appointment indexes") { db in
        try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_appointments_patientID"
            ON "appointments"("patientID")
            """
        )
        .execute(db)

        try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_appointments_start"
            ON "appointments"("start")
            """
        )
        .execute(db)
    }

    try migrator.migrate(database)
}

nonisolated private let databaseLogger = Logger(
    subsystem: "in.bitehaus.clinical-swift",
    category: "Database"
)

#if DEBUG
extension DatabaseWriter {
    func seedSampleDataIfNeeded() throws {
        try write { db in
            let patientCount = try PatientRecord.count().fetchOne(db) ?? 0
            guard patientCount == 0 else {
                return
            }

            var patients = samplePatients
            for appointment in sampleAppointments
            where !patients.contains(where: { $0.name == appointment.patientName }) {
                patients.append(Patient(
                    name: appointment.patientName,
                    createdDate: appointment.start
                ))
            }

            for patient in patients {
                try PatientRecord.insert { PatientRecord(patient) }
                    .execute(db)
            }

            let patientIDsByName = Dictionary(
                uniqueKeysWithValues: patients.compactMap { patient in
                    patient.name.map { ($0, patient.id) }
                }
            )

            for appointment in sampleAppointments {
                guard let patientID = patientIDsByName[appointment.patientName] else {
                    continue
                }
                try AppointmentRecord.insert {
                    AppointmentRecord(
                        id: appointment.id,
                        patientID: patientID,
                        start: appointment.start,
                        durationMinutes: appointment.durationMinutes,
                        status: appointment.status.storageValue,
                        createdAt: appointment.start,
                        updatedAt: appointment.start
                    )
                }
                .execute(db)
            }
        }
    }
}
#endif
