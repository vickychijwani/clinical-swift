import Foundation
import SQLiteData

@Selection
nonisolated struct ScheduleAppointmentRow: Identifiable, Sendable {
    let id: UUID
    let patientName: String?
    let start: Date
    let durationMinutes: Int
    let status: String

    var appointment: Appointment? {
        guard let status = Appointment.Status(storageValue: status) else {
            return nil
        }
        return Appointment(
            id: id,
            patientName: patientName ?? Patient.unknownDisplayName,
            start: start,
            durationMinutes: durationMinutes,
            status: status
        )
    }
}

nonisolated func querySchedule(selectedDate: Date) -> some Statement<ScheduleAppointmentRow> {
    let calendar = Calendar.autoupdatingCurrent
    let start = selectedDate.startOfDay(using: calendar)
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

    return
        AppointmentRecord
        .where { $0.start >= start }
        .where { $0.start < end }
        .order { $0.start.asc() }
        .join(PatientRecord.all) { $0.patientID.eq($1.id) }
        .select { appt, patient in
            ScheduleAppointmentRow.Columns(
                id: appt.id,
                patientName: patient.name,
                start: appt.start,
                durationMinutes: appt.durationMinutes,
                status: appt.status
            )
        }
}
