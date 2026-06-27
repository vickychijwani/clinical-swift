import Foundation
import SQLiteData

@MainActor @Observable class ScheduleModel {
    var selectedDate: Date

    @ObservationIgnored @Dependency(\.calendar) var calendar
    @ObservationIgnored @FetchAll(ScheduleAppointmentRow.none) var appointmentRows

    init(selectedDate: Date) {
        self.selectedDate = selectedDate
    }

    var appointments: [Appointment] {
        appointmentRows.compactMap(\.appointment)
    }

    func load() async throws {
        try await $appointmentRows.load(querySchedule(selectedDate: selectedDate))
    }
}
