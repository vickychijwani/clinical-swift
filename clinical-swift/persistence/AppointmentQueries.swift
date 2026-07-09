import Foundation
import SQLiteData

@Selection
nonisolated struct AppointmentPatientSelection: Identifiable, Sendable {
    let appointmentRecord: AppointmentRecord
    let patientRecord: PatientRecord

    var id: Appointment.ID { appointmentRecord.id }

    var details: AppointmentDetails? {
        let patient = Patient(patientRecord)
        guard
            let appointment = appointmentRecord.appointment(
                patientName: patient.displayName
            )
        else {
            return nil
        }

        return AppointmentDetails(
            appointment: appointment,
            patient: patient
        )
    }
}

nonisolated func querySchedule(
    selectedDate: Date
) -> some Statement<AppointmentPatientSelection> {
    let calendar = Calendar.autoupdatingCurrent
    let start = selectedDate.startOfDay(using: calendar)
    let endExclusive = calendar.date(byAdding: .day, value: 1, to: start) ?? start

    return scheduleAppointmentsQuery(start: start, endExclusive: endExclusive)
}

nonisolated func queryScheduleWindow(
    centeredOn selectedDate: Date
) -> some Statement<AppointmentPatientSelection> {
    let calendar = Calendar.autoupdatingCurrent
    let center = selectedDate.startOfDay(using: calendar)
    let start = center.date(byAddingDays: -1, using: calendar)
    let endExclusive = center.date(byAddingDays: 2, using: calendar)

    return scheduleAppointmentsQuery(start: start, endExclusive: endExclusive)
}

nonisolated private func scheduleAppointmentsQuery(
    start: Date,
    endExclusive: Date
) -> some Statement<AppointmentPatientSelection> {
    return
        AppointmentRecord
        .where { $0.start >= start }
        .where { $0.start < endExclusive }
        .where { $0.status.neq(Appointment.Status.cancelled.rawValue) }
        .order { $0.start.asc() }
        .join(PatientRecord.all) { $0.patientID.eq($1.id) }
        .select { appointment, patient in
            AppointmentPatientSelection.Columns(
                appointmentRecord: appointment,
                patientRecord: patient
            )
        }
}

nonisolated func appointmentDetailsQuery(
    id: Appointment.ID
) -> some Statement<AppointmentPatientSelection> {
    AppointmentRecord
        .where { $0.id.eq(id) }
        .where { $0.status.neq(Appointment.Status.cancelled.rawValue) }
        .join(PatientRecord.all) { $0.patientID.eq($1.id) }
        .select { appointment, patient in
            AppointmentPatientSelection.Columns(
                appointmentRecord: appointment,
                patientRecord: patient
            )
        }
}

nonisolated func patientTimelineAppointmentsQuery(
    patientID: Patient.ID
) -> some Statement<AppointmentRecord> {
    AppointmentRecord
        .where { $0.patientID.eq(patientID) }
        .where {
            $0.status.in([
                Appointment.Status.scheduled.rawValue,
                Appointment.Status.completed.rawValue,
            ])
        }
        .order { ($0.start.desc(), $0.createdAt.desc(), $0.id.desc()) }
        .selectStar()
}
