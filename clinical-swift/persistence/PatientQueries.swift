import Foundation
import SQLiteData

@Selection
nonisolated struct PatientDetailsSelection: Identifiable, Sendable {
    let patientRecord: PatientRecord
    let nextAppointmentDate: Date?

    var id: Patient.ID { patientRecord.id }

    var details: PatientDetails {
        PatientDetails(
            patient: Patient(patientRecord),
            nextAppointmentDate: nextAppointmentDate
        )
    }
}

nonisolated func patientListRowsQuery(
    now: Date = .now
) -> some Statement<PatientDetailsSelection> {
    let orderedPatients =
        PatientRecord
        .group(by: \.id)
        .order { patient in
            (
                patient.name.is(nil),
                patient.name.ifnull("").collate(.nocase),
                patient.createdAt
            )
        }

    return
        orderedPatients
        .leftJoin(AppointmentRecord.all) { patient, appointment in
            patient.id.eq(appointment.patientID)
                && appointment.start >= now
                && appointment.status.eq(Appointment.Status.scheduled.rawValue)
        }
        .select { patient, appointment in
            PatientDetailsSelection.Columns(
                patientRecord: patient,
                nextAppointmentDate: appointment.start.min()
            )
        }
}

nonisolated func patientDetailsQuery(
    id: Patient.ID,
    now: Date = .now
) -> some Statement<PatientDetailsSelection> {
    PatientRecord
        .where { $0.id.eq(id) }
        .group(by: \.id)
        .leftJoin(AppointmentRecord.all) { patient, appointment in
            patient.id.eq(appointment.patientID)
                && appointment.start >= now
                && appointment.status.eq(Appointment.Status.scheduled.rawValue)
        }
        .select { patient, appointment in
            PatientDetailsSelection.Columns(
                patientRecord: patient,
                nextAppointmentDate: appointment.start.min()
            )
        }
}
