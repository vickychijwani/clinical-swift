import ClinicalModels
import ClinicalPersistence
import Foundation
import SQLiteData

@MainActor @Observable final class AppointmentBookingModel {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.date.now) private var now

    let purpose: AppointmentBookingPurpose
    private let draftAppointmentID: Appointment.ID
    var draft: AppointmentBookingDraft
    var searchText = ""

    init(
        selectedDate: Date,
        selectedPatient: Patient? = nil
    ) {
        self.purpose = .create
        self.draftAppointmentID = UUID()
        self.draft = AppointmentBookingDraft(
            selectedPatient: selectedPatient,
            selectedDate: selectedDate
        )
    }

    init(
        editing details: AppointmentDetails
    ) {
        let appointment = details.appointment
        self.purpose = .edit(appointment.id)
        self.draftAppointmentID = appointment.id
        self.draft = AppointmentBookingDraft(
            selectedPatient: details.patient,
            selectedDate: appointment.start,
            start: appointment.start,
            durationMinutes: appointment.durationMinutes
        )
    }

    var draftAppointment: Appointment {
        Appointment(
            id: draftAppointmentID,
            patientName: draft.selectedPatient?.displayName ?? "<Select a patient>",
            start: draft.start,
            durationMinutes: draft.durationMinutes,
            status: .draft
        )
    }

    func save() async throws -> Date {
        try draft.normalized.validate()
        // Keep the result tied to the value being saved, even if the draft changes while the
        // database write suspends this method.
        let savedDate = draft.start
        switch purpose {
        case .create:
            let record = try draft.normalized.makeRecord(id: draftAppointmentID, now: now)
            try await database.write { db in
                try AppointmentRecord.insert { record }
                    .execute(db)
            }

        case .edit(let appointmentID):
            guard let patientID = draft.selectedPatient?.id else {
                throw AppointmentBookingValidationError.missingPatient
            }
            // Pass one immutable snapshot into the database closure instead of accessing the
            // model's actor-isolated draft and clock from inside the write.
            let start = draft.start
            let durationMinutes = draft.durationMinutes
            let updatedAt = now

            try await database.write { db in
                // Ensure the stored appointment status hasn't changed while editing
                guard
                    let record = try AppointmentRecord.find(appointmentID).fetchOne(db),
                    record.status == Appointment.Status.scheduled.rawValue
                else {
                    throw AppointmentEditingError.unavailable
                }

                try validateAppointmentPatientChange(
                    id: appointmentID, patientID: patientID, in: db)
                try AppointmentRecord.find(appointmentID)
                    .update {
                        $0.patientID = patientID
                        $0.start = start
                        $0.durationMinutes = durationMinutes
                        $0.updatedAt = updatedAt
                    }
                    .execute(db)
            }
        }

        return savedDate
    }

}

nonisolated enum AppointmentBookingPurpose: Equatable, Sendable {
    case create
    case edit(Appointment.ID)

    var editedAppointmentID: Appointment.ID? {
        guard case .edit(let id) = self else { return nil }
        return id
    }
}
