import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData

@MainActor @Observable final class AppointmentBookingModel {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.telemetry) private var telemetry

    let purpose: AppointmentBookingPurpose
    private let draftAppointmentID: Appointment.ID
    private let originalStart: Date?
    var draft: AppointmentBookingDraft
    var searchText = ""

    struct SavedAppointment: Equatable, Sendable {
        let id: Appointment.ID
        let start: Date
        let kind: Kind

        enum Kind: Equatable, Sendable {
            case booked
            case rescheduled
            case updated
        }
    }

    init(
        selectedDate: Date,
        selectedPatient: Patient? = nil
    ) {
        self.purpose = .create
        self.draftAppointmentID = UUID()
        self.originalStart = nil
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
        self.originalStart = appointment.start
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

    func save() async throws -> SavedAppointment {
        try draft.normalized.validate()
        // Keep the result tied to the value being saved, even if the draft changes while the
        // database write suspends this method.
        let savedDate = draft.start
        let savedDuration = draft.durationMinutes
        let action = purpose.editedAppointmentID == nil ? "create" : "edit"
        do {
            switch purpose {
            case .create:
                let record = try draft.normalized.makeRecord(id: draftAppointmentID, now: now)
                try await database.write { db in
                    try AppointmentRecord.insert { record }
                        .execute(db)
                }
                telemetry.event(
                    category: .appointment,
                    name: "appointment_booked",
                    recordID: draftAppointmentID.uuidString.lowercased(),
                    action: action
                )
                return SavedAppointment(id: draftAppointmentID, start: savedDate, kind: .booked)

            case .edit(let appointmentID):
                guard let patientID = draft.selectedPatient?.id else {
                    throw AppointmentBookingValidationError.missingPatient
                }
                // Pass one immutable snapshot into the database closure instead of accessing the
                // model's actor-isolated draft and clock from inside the write.
                let start = savedDate
                let durationMinutes = savedDuration
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
                // Only a start-time change counts as rescheduled; confirmation messages omit duration.
                let didReschedule = originalStart.map { $0 != start } ?? false
                telemetry.event(
                    category: .appointment,
                    name: didReschedule ? "appointment_rescheduled" : "appointment_updated",
                    recordID: appointmentID.uuidString.lowercased(),
                    action: action
                )
                return SavedAppointment(
                    id: appointmentID,
                    start: savedDate,
                    kind: didReschedule ? .rescheduled : .updated
                )
            }
        } catch {
            telemetry.log(
                .error,
                category: .appointment,
                name: "appointment_save_failed",
                message: "Appointment save failed",
                error: error,
                recordID: draftAppointmentID.uuidString.lowercased(),
                action: action
            )
            throw error
        }
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
