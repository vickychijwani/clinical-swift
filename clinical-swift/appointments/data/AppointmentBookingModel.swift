import Foundation
import SQLiteData

@Observable class AppointmentBookingModel {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.calendar) var calendar
    @ObservationIgnored @FetchAll(ScheduleAppointmentRow.none) var appointmentRows

    var selectedDate: Date {
        didSet {
            draft.selectDate(selectedDate)
            Task { try? await load() }
        }
    }

    var draft: AppointmentBookingDraft
    var searchText = ""
    var isSaving = false
    var saveErrorMessage: String?
    var onBooked: (Date) -> Void

    init(selectedDate: Date,
         selectedPatient: PatientDetails? = nil,
         onBooked: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.draft = AppointmentBookingDraft(
            selectedPatient: selectedPatient,
            selectedDate: selectedDate
        )
        self.onBooked = onBooked
    }

    var appointments: [Appointment] {
        print(appointmentRows)
        return appointmentRows.compactMap(\.appointment)
    }

    func load() async throws {
        try await $appointmentRows.load(querySchedule(selectedDate: selectedDate))
    }

    func saveAppointment() {
        let record: AppointmentRecord

        do {
            record = try draft.normalized.makeRecord(now: .now)
            // Reset error message
            saveErrorMessage = nil
        } catch AppointmentBookingValidationError.missingPatient {
            saveErrorMessage = "Select a patient."
            return
        } catch AppointmentBookingValidationError.invalidTime {
            saveErrorMessage = "Choose a time within clinic hours."
            return
        } catch {
            saveErrorMessage = "Check the appointment details and try again."
            return
        }

        isSaving = true
        Task {
            do {
                try await database.write { db in
                    try AppointmentRecord.insert { record }
                        .execute(db)
                }
                onBooked(draft.selectedDate)
            } catch {
                saveErrorMessage = "The appointment could not be saved."
            }
            isSaving = false
        }
    }
}
