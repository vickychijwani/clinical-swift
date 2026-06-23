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

nonisolated func querySchedule(selectedDate: Date) -> some Statement<ScheduleAppointmentRow> {
    let calendar = Calendar.autoupdatingCurrent
    let startTime = selectedDate.startOfDay(using: calendar)
    let endTime = calendar.date(byAdding: .day, value: 1, to: startTime) ?? startTime

    return AppointmentRecord
        .where { $0.startTime >= startTime }
        .where { $0.startTime < endTime }
        .order { $0.startTime.asc() }
        .join(PatientRecord.all) { $0.patientID.eq($1.id) }
        .select { appt, patient in
            ScheduleAppointmentRow.Columns(
                id: appt.id,
                patientName: patient.name,
                startTime: appt.startTime,
                durationMinutes: appt.durationMinutes,
                status: appt.status
            )
        }
}
