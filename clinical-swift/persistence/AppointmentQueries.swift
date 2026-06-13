import Foundation
import SQLiteData

@Selection
nonisolated struct ScheduleAppointmentRow: Identifiable, Sendable {
    let id: UUID
    let patientName: String?
    let startTime: Date
    let durationMinutes: Int
    let status: String

    var appointment: Appointment? {
        guard let status = Appointment.Status(storageValue: status) else {
            return nil
        }
        return Appointment(
            id: id,
            patientName: patientName ?? Patient.unknownDisplayName,
            startTime: startTime,
            durationMinutes: durationMinutes,
            status: status
        )
    }
}

nonisolated func scheduleAppointmentsQuery(selectedDate: Date) -> some Statement<ScheduleAppointmentRow> {
    let calendar = Calendar.autoupdatingCurrent
    let startDate = selectedDate.startOfDay(using: calendar)
    let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
    return scheduleAppointmentsQuery(startDate: startDate, endDate: endDate)
}

nonisolated func scheduleAppointmentsQuery(
    startDate: Date,
    endDate: Date
) -> some Statement<ScheduleAppointmentRow> {
    #sql(
        """
        SELECT
          "appointments"."id",
          "patients"."name" AS "patientName",
          "appointments"."startTime",
          "appointments"."durationMinutes",
          "appointments"."status"
        FROM "appointments"
        INNER JOIN "patients"
          ON "patients"."id" = "appointments"."patientID"
        WHERE "appointments"."startTime" >= \(startDate)
          AND "appointments"."startTime" < \(endDate)
        ORDER BY "appointments"."startTime"
        """
    )
}
