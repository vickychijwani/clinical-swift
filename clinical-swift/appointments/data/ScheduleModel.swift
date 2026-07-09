import Foundation
import SQLiteData

@MainActor @Observable class ScheduleModel {
    var selectedDate: Date

    @ObservationIgnored @Dependency(\.calendar) var calendar
    @ObservationIgnored @FetchAll(AppointmentPatientSelection.none) private var appointmentRows

    init(selectedDate: Date) {
        self.selectedDate = selectedDate.startOfDay()
    }

    var appointments: [Appointment] {
        appointments(for: selectedDate)
    }

    func appointments(for date: Date) -> [Appointment] {
        let selectedDate = date.startOfDay(using: calendar)
        return
            appointmentRows
            .compactMap { $0.details?.appointment }
            .filter { calendar.isDate($0.start, inSameDayAs: selectedDate) }
    }

    func details(for appointment: Appointment) -> AppointmentDetails? {
        appointmentRows.first(where: { $0.id == appointment.id })?.details
    }

    func load(dayRadius: Int) async throws {
        try await loadVisibleDays(centeredOn: selectedDate, dayRadius: dayRadius)
    }

    func loadVisibleDays(centeredOn date: Date, dayRadius: Int) async throws {
        let centerDate = date.startOfDay(using: calendar)
        guard calendar.isDate(centerDate, inSameDayAs: selectedDate) else {
            return
        }

        try await $appointmentRows.load(
            queryScheduleWindow(centeredOn: centerDate, dayRadius: dayRadius)
        )
    }
}
