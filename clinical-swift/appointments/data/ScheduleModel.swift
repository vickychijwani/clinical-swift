import Foundation
import SQLiteData

@Observable class ScheduleModel {
    var selectedDate: Date {
        didSet { Task { try? await load() } }
    }

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
