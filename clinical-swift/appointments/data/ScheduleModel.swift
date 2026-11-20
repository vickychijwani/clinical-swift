import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData

/// A query-backed cache for explicitly requested schedule days. Selection intentionally belongs to
/// `Router`, because external appointment and schedule entry points must update the visible day too.
@MainActor @Observable class ScheduleModel {
    @ObservationIgnored @Dependency(\.calendar) var calendar
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.telemetry) private var telemetry
    @ObservationIgnored @FetchAll(AppointmentPatientSelection.none) private var appointmentRows

    @ObservationIgnored @FetchAll(UnavailableTimeRecord.none) private var unavailableTimeRows
    @ObservationIgnored private var loadedWindow: ClosedRange<Date>?

    func unavailableTimes(for date: Date) -> [UnavailableTime] {
        unavailableTimeRows.map(\.unavailableTime).filter {
            calendar.isDate($0.start, inSameDayAs: date)
        }
    }

    func appointments(for date: Date) -> [Appointment] {
        let selectedDate = date.startOfDay(using: calendar)
        return
            appointmentRows
            .compactMap { $0.details?.appointment }
            .filter { calendar.isDate($0.start, inSameDayAs: selectedDate) }
    }

    /// Reads the target day from storage when booking jumps outside the loaded timeline window.
    func appointmentsForBooking(on date: Date) async -> [Appointment] {
        let day = date.startOfDay(using: calendar)
        if let loadedWindow, loadedWindow.contains(day) {
            return appointments(for: day)
        }
        let query = querySchedule(selectedDate: day, calendar: calendar)
        do {
            let rows = try await database.read { db in
                try query.fetchAll(db)
            }
            return rows.compactMap { $0.details?.appointment }
        } catch {
            telemetry.log(
                .error,
                category: .schedule,
                name: "schedule_booking_read_failed",
                message: "Could not read schedule day for booking",
                error: error
            )
            return []
        }
    }

    func details(for appointment: Appointment) -> AppointmentDetails? {
        appointmentRows.first(where: { $0.id == appointment.id })?.details
    }

    func loadVisibleDays(centeredOn date: Date, dayRadius: Int) async throws {
        let centerDate = date.startOfDay(using: calendar)
        let radius = max(dayRadius, 1)
        do {
            try await $unavailableTimeRows.load(
                unavailableTimesQuery(centeredOn: centerDate, dayRadius: dayRadius)
            )
            try await $appointmentRows.load(
                queryScheduleWindow(centeredOn: centerDate, dayRadius: dayRadius)
            )
        } catch {
            telemetry.log(
                .error,
                category: .schedule,
                name: "schedule_load_failed",
                message: "Could not load visible schedule window",
                error: error
            )
            throw error
        }
        let start = centerDate.date(byAddingDays: -radius, using: calendar)
        let end = centerDate.date(byAddingDays: radius, using: calendar)
        loadedWindow = start...end
        telemetry.event(
            category: .schedule,
            name: "schedule_window_loaded",
            level: .debug,
            count: appointmentRows.count + unavailableTimeRows.count
        )
    }
}
