import Foundation
import SQLiteData

/// A query-backed cache for explicitly requested schedule days. Selection intentionally belongs to
/// `Router`, because external appointment and schedule entry points must update the visible day too.
@MainActor @Observable class ScheduleModel {
    @ObservationIgnored @Dependency(\.calendar) var calendar
    @ObservationIgnored @FetchAll(AppointmentPatientSelection.none) private var appointmentRows

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

    func loadVisibleDays(centeredOn date: Date, dayRadius: Int) async throws {
        let centerDate = date.startOfDay(using: calendar)
        try await $appointmentRows.load(
            queryScheduleWindow(centeredOn: centerDate, dayRadius: dayRadius)
        )
    }
}
