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

    migrator.registerMigration("Normalize patient phone numbers") { db in
        let storedPhones = try String.fetchAll(
            db,
            sql: #"SELECT DISTINCT "phone" FROM "patients" WHERE "phone" IS NOT NULL"#
        )

        for storedPhone in storedPhones {
            let normalizedPhone = PhoneNumber.normalizedE164(storedPhone)
            try #sql(
                """
                UPDATE "patients"
                SET "phone" = \(bind: normalizedPhone)
                WHERE "phone" = \(bind: storedPhone)
                """
            )
            .execute(db)
        }

        try #sql(
            """
            CREATE TRIGGER "validate_patient_phone_before_insert"
            BEFORE INSERT ON "patients"
            WHEN NEW."phone" IS NOT NULL AND (
              length(NEW."phone") NOT BETWEEN 2 AND 16
              -- Require a plus and a nonzero first digit; GLOB's * can still match any characters.
              OR NEW."phone" NOT GLOB '+[1-9]*'
              -- Ensure every character after the plus is a digit.
              OR substr(NEW."phone", 2) GLOB '*[^0-9]*'
            )
            BEGIN
              SELECT RAISE(ABORT, 'patient phone must use E.164 format');
            END
            """
        )
        .execute(db)

        try #sql(
            """
            CREATE TRIGGER "validate_patient_phone_before_update"
            BEFORE UPDATE OF "phone" ON "patients"
            WHEN NEW."phone" IS NOT NULL AND (
              length(NEW."phone") NOT BETWEEN 2 AND 16
              -- Require a plus and a nonzero first digit; GLOB's * can still match any characters.
              OR NEW."phone" NOT GLOB '+[1-9]*'
              -- Ensure every character after the plus is a digit.
              OR substr(NEW."phone", 2) GLOB '*[^0-9]*'
            )
            BEGIN
              SELECT RAISE(ABORT, 'patient phone must use E.164 format');
            END
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
                    patients.append(
                        Patient(
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
                    let record = try AppointmentRecord.persisted(
                        id: appointment.id,
                        patientID: patientID,
                        start: appointment.start,
                        durationMinutes: appointment.durationMinutes,
                        status: appointment.status,
                        createdAt: appointment.start,
                        updatedAt: appointment.start
                    )
                    try AppointmentRecord.insert {
                        record
                    }
                    .execute(db)
                }
            }
        }
    }
#endif
