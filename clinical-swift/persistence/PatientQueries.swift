import Foundation
import SQLiteData

@Selection
nonisolated struct PatientListRow: Identifiable, Sendable {
    let id: UUID
    let name: String?
    let phone: String?
    let dob: Date?
    let gender: String?
    let nextAppointmentDate: Date?
    let createdAt: Date
    let updatedAt: Date

    var item: PatientListItem {
        PatientListItem(
            patient: Patient(record),
            nextAppointmentDate: nextAppointmentDate
        )
    }

    private var record: PatientRecord {
        PatientRecord(
            id: id,
            name: name,
            phone: phone,
            dob: dob,
            gender: gender,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

nonisolated func patientListRowsQuery(now: Date = .now) -> some Statement<PatientListRow> {
    #sql(
        """
        SELECT
          "patients"."id",
          "patients"."name",
          "patients"."phone",
          "patients"."dob",
          "patients"."gender",
          min("appointments"."startTime") AS "nextAppointmentDate",
          "patients"."createdAt",
          "patients"."updatedAt"
        FROM "patients"
        LEFT JOIN "appointments"
          ON "appointments"."patientID" = "patients"."id"
          AND "appointments"."startTime" >= \(now)
        GROUP BY "patients"."id"
        ORDER BY
          "patients"."name" IS NULL,
          "patients"."name" COLLATE NOCASE,
          "patients"."createdAt"
        """
    )
}
