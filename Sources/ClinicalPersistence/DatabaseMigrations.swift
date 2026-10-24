import ClinicalModels
import Foundation
import GRDB
import SQLiteData

public func migrateDatabase(_ database: any DatabaseWriter) throws {
    try databaseMigrator().migrate(database)
}

public func databaseMigrator(allowDebugErasure: Bool = true) -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = allowDebugErasure
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
                SET "phone" = \(#bind(normalizedPhone, as: String?.self))
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

    migrator.registerMigration("Create appointment Calendar sync outbox") { db in
        try #sql(
            """
            CREATE TABLE "appointmentCalendarSync" (
              "appointmentID" TEXT PRIMARY KEY NOT NULL,
              "eventIdentifier" TEXT,
              "eventStart" TEXT,
              "needsSync" INTEGER NOT NULL CHECK ("needsSync" IN (0, 1)),
              "revision" INTEGER NOT NULL,
              "createdAt" TEXT NOT NULL,
              "updatedAt" TEXT NOT NULL
            ) STRICT
            """
        )
        .execute(db)

        try #sql(
            """
            CREATE TRIGGER "queue_appointment_calendar_sync_after_insert"
            AFTER INSERT ON "appointments"
            BEGIN
              INSERT INTO "appointmentCalendarSync" (
                "appointmentID", "eventIdentifier", "eventStart", "needsSync",
                "revision", "createdAt", "updatedAt"
              ) VALUES (
                NEW."id", NULL, NULL, 1, 1,
                strftime('%Y-%m-%d %H:%M:%f', 'now'),
                strftime('%Y-%m-%d %H:%M:%f', 'now')
              )
              ON CONFLICT("appointmentID") DO UPDATE SET
                "needsSync" = 1,
                "revision" = "appointmentCalendarSync"."revision" + 1,
                "updatedAt" = strftime('%Y-%m-%d %H:%M:%f', 'now');
            END
            """
        )
        .execute(db)

        try #sql(
            """
            CREATE TRIGGER "queue_appointment_calendar_sync_after_schedule_update"
            AFTER UPDATE OF "patientID", "start", "durationMinutes" ON "appointments"
            WHEN OLD."patientID" IS NOT NEW."patientID"
              OR OLD."start" IS NOT NEW."start"
              OR OLD."durationMinutes" IS NOT NEW."durationMinutes"
            BEGIN
              INSERT INTO "appointmentCalendarSync" (
                "appointmentID", "eventIdentifier", "eventStart", "needsSync",
                "revision", "createdAt", "updatedAt"
              ) VALUES (
                NEW."id", NULL, NULL, 1, 1,
                strftime('%Y-%m-%d %H:%M:%f', 'now'),
                strftime('%Y-%m-%d %H:%M:%f', 'now')
              )
              ON CONFLICT("appointmentID") DO UPDATE SET
                "needsSync" = 1,
                "revision" = "appointmentCalendarSync"."revision" + 1,
                "updatedAt" = strftime('%Y-%m-%d %H:%M:%f', 'now');
            END
            """
        )
        .execute(db)

        try #sql(
            """
            CREATE TRIGGER "queue_appointment_calendar_sync_after_cancellation"
            AFTER UPDATE OF "status" ON "appointments"
            WHEN NEW."status" = 'cancelled' AND OLD."status" IS NOT NEW."status"
            BEGIN
              INSERT INTO "appointmentCalendarSync" (
                "appointmentID", "eventIdentifier", "eventStart", "needsSync",
                "revision", "createdAt", "updatedAt"
              ) VALUES (
                NEW."id", NULL, NULL, 1, 1,
                strftime('%Y-%m-%d %H:%M:%f', 'now'),
                strftime('%Y-%m-%d %H:%M:%f', 'now')
              )
              ON CONFLICT("appointmentID") DO UPDATE SET
                "needsSync" = 1,
                "revision" = "appointmentCalendarSync"."revision" + 1,
                "updatedAt" = strftime('%Y-%m-%d %H:%M:%f', 'now');
            END
            """
        )
        .execute(db)

        try #sql(
            """
            CREATE TRIGGER "queue_appointment_calendar_sync_after_delete"
            AFTER DELETE ON "appointments"
            BEGIN
              INSERT INTO "appointmentCalendarSync" (
                "appointmentID", "eventIdentifier", "eventStart", "needsSync",
                "revision", "createdAt", "updatedAt"
              ) VALUES (
                OLD."id", NULL, NULL, 1, 1,
                strftime('%Y-%m-%d %H:%M:%f', 'now'),
                strftime('%Y-%m-%d %H:%M:%f', 'now')
              )
              ON CONFLICT("appointmentID") DO UPDATE SET
                "needsSync" = 1,
                "revision" = "appointmentCalendarSync"."revision" + 1,
                "updatedAt" = strftime('%Y-%m-%d %H:%M:%f', 'now');
            END
            """
        )
        .execute(db)

        try #sql(
            """
            CREATE TRIGGER "queue_appointment_calendar_sync_after_patient_update"
            AFTER UPDATE OF "name", "phone" ON "patients"
            WHEN OLD."name" IS NOT NEW."name" OR OLD."phone" IS NOT NEW."phone"
            BEGIN
              INSERT INTO "appointmentCalendarSync" (
                "appointmentID", "eventIdentifier", "eventStart", "needsSync",
                "revision", "createdAt", "updatedAt"
              )
              SELECT
                "id", NULL, NULL, 1, 1,
                strftime('%Y-%m-%d %H:%M:%f', 'now'),
                strftime('%Y-%m-%d %H:%M:%f', 'now')
              FROM "appointments"
              WHERE "patientID" = NEW."id" AND "status" != 'cancelled'
              ON CONFLICT("appointmentID") DO UPDATE SET
                "needsSync" = 1,
                "revision" = "appointmentCalendarSync"."revision" + 1,
                "updatedAt" = strftime('%Y-%m-%d %H:%M:%f', 'now');
            END
            """
        )
        .execute(db)
    }

    migrator.registerMigration("Create unavailable time table") { db in
        try db.execute(
            sql:
                """
                CREATE TABLE "unavailableTimes" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                  "label" TEXT,
                  "start" TEXT NOT NULL,
                  "durationMinutes" INTEGER NOT NULL CHECK ("durationMinutes" > 0),
                  "createdAt" TEXT NOT NULL,
                  "updatedAt" TEXT NOT NULL
                ) STRICT;
                CREATE INDEX "idx_unavailableTimes_start" ON "unavailableTimes"("start");
                """
        )
    }

    migrator.registerMigration("Create unavailable time Calendar sync outbox") { db in
        try db.execute(
            sql:
                """
                CREATE TABLE "unavailableTimeCalendarSync" (
                  "unavailableTimeID" TEXT PRIMARY KEY NOT NULL,
                  "eventIdentifier" TEXT,
                  "eventStart" TEXT,
                  "needsSync" INTEGER NOT NULL CHECK ("needsSync" IN (0, 1)),
                  "revision" INTEGER NOT NULL,
                  "createdAt" TEXT NOT NULL,
                  "updatedAt" TEXT NOT NULL
                ) STRICT;
                CREATE TRIGGER "queue_unavailable_time_calendar_sync_after_insert"
                AFTER INSERT ON "unavailableTimes"
                BEGIN
                  INSERT INTO "unavailableTimeCalendarSync" (
                    "unavailableTimeID", "eventIdentifier", "eventStart", "needsSync",
                    "revision", "createdAt", "updatedAt"
                  ) VALUES (
                    NEW."id", NULL, NULL, 1, 1,
                    strftime('%Y-%m-%d %H:%M:%f', 'now'),
                    strftime('%Y-%m-%d %H:%M:%f', 'now')
                  )
                  ON CONFLICT("unavailableTimeID") DO UPDATE SET
                    "needsSync" = 1,
                    "revision" = "unavailableTimeCalendarSync"."revision" + 1,
                    "updatedAt" = strftime('%Y-%m-%d %H:%M:%f', 'now');
                END;
                CREATE TRIGGER "queue_unavailable_time_calendar_sync_after_update"
                AFTER UPDATE OF "label", "start", "durationMinutes" ON "unavailableTimes"
                WHEN OLD."label" IS NOT NEW."label"
                  OR OLD."start" IS NOT NEW."start"
                  OR OLD."durationMinutes" IS NOT NEW."durationMinutes"
                BEGIN
                  INSERT INTO "unavailableTimeCalendarSync" (
                    "unavailableTimeID", "eventIdentifier", "eventStart", "needsSync",
                    "revision", "createdAt", "updatedAt"
                  ) VALUES (
                    NEW."id", NULL, NULL, 1, 1,
                    strftime('%Y-%m-%d %H:%M:%f', 'now'),
                    strftime('%Y-%m-%d %H:%M:%f', 'now')
                  )
                  ON CONFLICT("unavailableTimeID") DO UPDATE SET
                    "needsSync" = 1,
                    "revision" = "unavailableTimeCalendarSync"."revision" + 1,
                    "updatedAt" = strftime('%Y-%m-%d %H:%M:%f', 'now');
                END;
                CREATE TRIGGER "queue_unavailable_time_calendar_sync_after_delete"
                AFTER DELETE ON "unavailableTimes"
                BEGIN
                  INSERT INTO "unavailableTimeCalendarSync" (
                    "unavailableTimeID", "eventIdentifier", "eventStart", "needsSync",
                    "revision", "createdAt", "updatedAt"
                  ) VALUES (
                    OLD."id", NULL, NULL, 1, 1,
                    strftime('%Y-%m-%d %H:%M:%f', 'now'),
                    strftime('%Y-%m-%d %H:%M:%f', 'now')
                  )
                  ON CONFLICT("unavailableTimeID") DO UPDATE SET
                    "needsSync" = 1,
                    "revision" = "unavailableTimeCalendarSync"."revision" + 1,
                    "updatedAt" = strftime('%Y-%m-%d %H:%M:%f', 'now');
                END;
                """
        )
    }

    migrator.registerMigration("Create financial ledger and patient balances") { db in
        try createAccountEntrySchema(db)
    }

    return migrator
}
