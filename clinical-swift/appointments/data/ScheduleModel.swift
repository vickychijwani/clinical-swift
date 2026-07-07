import Foundation
import SQLiteData

@MainActor @Observable class ScheduleModel {
    var selectedDate: Date

    @ObservationIgnored @Dependency(\.calendar) var calendar
    @ObservationIgnored @FetchAll(AppointmentPatientSelection.none) var appointmentRows

    init(selectedDate: Date) {
        self.selectedDate = selectedDate
    }

    var appointments: [Appointment] {
        appointmentRows.compactMap { $0.details?.appointment }
    }

    func details(for appointment: Appointment) -> AppointmentDetails? {
        appointmentRows.first(where: { $0.id == appointment.id })?.details
    }

    func load() async throws {
        try await $appointmentRows.load(querySchedule(selectedDate: selectedDate))
    }
}
