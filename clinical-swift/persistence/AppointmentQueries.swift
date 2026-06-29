import Foundation
import SQLiteData

@Selection
nonisolated struct ScheduleAppointmentRow: Identifiable, Sendable {
    let id: UUID
    let patientID: UUID
    let patientName: String?
    let patientPhone: String?
    let patientDOB: Date?
    let patientGender: String?
    let patientCreatedAt: Date
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

    var details: AppointmentDetails? {
        guard let appointment else {
            return nil
        }

        return AppointmentDetails(
            appointment: appointment,
            patient: Patient(
                id: patientID,
                name: patientName,
                phone: patientPhone,
                dob: patientDOB,
                gender: patientGender.flatMap(Gender.init(storageValue:)),
                createdDate: patientCreatedAt
            )
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
                patientID: patient.id,
                patientName: patient.name,
                patientPhone: patient.phone,
                patientDOB: patient.dob,
                patientGender: patient.gender,
                patientCreatedAt: patient.createdAt,
                start: appt.start,
                durationMinutes: appt.durationMinutes,
                status: appt.status
            )
        }
}

nonisolated func appointmentDetailsQuery(
    id: Appointment.ID
) -> some Statement<ScheduleAppointmentRow> {
    AppointmentRecord
        .where { $0.id.eq(id) }
        .join(PatientRecord.all) { $0.patientID.eq($1.id) }
        .select { appt, patient in
            ScheduleAppointmentRow.Columns(
                id: appt.id,
                patientID: patient.id,
                patientName: patient.name,
                patientPhone: patient.phone,
                patientDOB: patient.dob,
                patientGender: patient.gender,
                patientCreatedAt: patient.createdAt,
                start: appt.start,
                durationMinutes: appt.durationMinutes,
                status: appt.status
            )
        }
}
