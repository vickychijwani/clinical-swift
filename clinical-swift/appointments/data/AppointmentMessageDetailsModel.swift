import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData

@MainActor @Observable
final class AppointmentMessageDetailsModel {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @FetchOne private var row: AppointmentPatientSelection?

    let appointmentID: Appointment.ID
    private(set) var messageModel: AppointmentMessageModel?
    private(set) var errorMessage: String?
    private(set) var isLoading = true

    init(appointmentID: Appointment.ID) {
        self.appointmentID = appointmentID
        _row = FetchOne(appointmentDetailsQuery(id: appointmentID))
    }

    var details: AppointmentDetails? {
        row?.details
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            try await $row.load(appointmentDetailsQuery(id: appointmentID))
            guard let details else {
                messageModel = nil
                return
            }
            guard details.appointment.status == .scheduled else {
                errorMessage = "Appointment messaging is only available for scheduled appointments."
                messageModel = nil
                return
            }

            let firstVisibleAppointment = try await database.read { db in
                try earliestVisibleAppointmentQuery(patientID: details.patient.id).fetchOne(db)
            }
            messageModel = AppointmentMessageModel(
                details: details,
                includesLocation: firstVisibleAppointment?.id == details.appointment.id
            )
        } catch {
            errorMessage = "Appointment messaging could not be loaded."
            messageModel = nil
        }
    }
}
