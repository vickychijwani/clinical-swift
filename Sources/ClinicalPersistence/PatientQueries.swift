import ClinicalModels
import Foundation
import SQLiteData

@Selection
public nonisolated struct PatientDetailsSelection: Identifiable, Sendable {
    public let patientRecord: PatientRecord
    public let nextAppointmentDate: Date?
    public let currentBalance: Int

    public var id: Patient.ID { patientRecord.id }

    public var details: PatientDetails {
        PatientDetails(
            patient: Patient(patientRecord),
            nextAppointmentDate: nextAppointmentDate,
            currentBalance: currentBalance
        )
    }
}

public nonisolated func patientListRowsQuery(
    now: Date = .now,
    owingOnly: Bool = false
) -> some Statement<PatientDetailsSelection> & Sendable {
    let orderedPatients =
        PatientRecord
        .where { patient in
            if owingOnly {
                patient.id.in(PatientBalanceRecord.where { $0.balance > 0 }.select { $0.id })
            }
        }
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
        .leftJoin(PatientBalanceRecord.all) { patient, _, balance in
            patient.id.eq(balance.id)
        }
        .select { patient, appointment, balance in
            PatientDetailsSelection.Columns(
                patientRecord: patient,
                nextAppointmentDate: appointment.start.min(),
                currentBalance: balance.balance.ifnull(0)
            )
        }
}

public nonisolated func patientDetailsQuery(
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
        .leftJoin(PatientBalanceRecord.all) { patient, _, balance in
            patient.id.eq(balance.id)
        }
        .select { patient, appointment, balance in
            PatientDetailsSelection.Columns(
                patientRecord: patient,
                nextAppointmentDate: appointment.start.min(),
                currentBalance: balance.balance.ifnull(0)
            )
        }
}

public nonisolated func appointmentBookingPatientRowsQuery(
    now: Date
) -> some Statement<PatientDetailsSelection> & Sendable {
    let cutoff: Date? = now
    let patientsWithAppointments =
        PatientRecord
        .group(by: \.id)
        .leftJoin(AppointmentRecord.all) { patient, appointment in
            patient.id.eq(appointment.patientID)
                && appointment.status.in([
                    Appointment.Status.scheduled.rawValue,
                    Appointment.Status.completed.rawValue,
                ])
        }

    return
        patientsWithAppointments
        .order { patient, appointment in
            // Use the later of patient creation and a past visit. Future visits must not
            // move a patient ahead of a recent visit or a newly created patient.
            let recency = Case()
                .when(
                    appointment.start.ifnull(patient.createdAt) > patient.createdAt,
                    then: appointment.start.ifnull(patient.createdAt)
                )
                .else(patient.createdAt)
                .max(filter: appointment.start <= cutoff)
                .ifnull(patient.createdAt)
            (
                recency.desc(),
                patient.name.is(nil),
                patient.name.ifnull("").collate(.nocase),
                patient.id.asc()
            )
        }
        .leftJoin(PatientBalanceRecord.all) { patient, _, balance in
            patient.id.eq(balance.id)
        }
        .select { patient, appointment, balance in
            PatientDetailsSelection.Columns(
                patientRecord: patient,
                nextAppointmentDate: appointment.start.min(
                    filter: appointment.start >= cutoff
                        && appointment.status.eq(Appointment.Status.scheduled.rawValue)
                ),
                currentBalance: balance.balance.ifnull(0)
            )
        }
}
