import Foundation
import Testing

@testable import clinical_swift

struct AppointmentAvailabilityTests {
    @Test func manualStartCanFitEvenWhenItIsBeforePreferredAutomaticStart() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let availability = AppointmentAvailability(
            searchDate: selectedDate,
            appointments: [],
            calendar: calendar
        )

        #expect(
            availability.canPrefill(
                start: selectedDate.setTime(9, 30, using: calendar),
                durationMinutes: 30
            )
        )
        #expect(
            availability.firstAvailableSlot(neededDurationMinutes: 30)
                == selectedDate.setTime(10, 0, using: calendar)
        )
    }

    @Test func overlappingStartIsNotUsedForPrefill() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let existingAppointment = Appointment(
            patientName: "Aarav Mehta",
            start: selectedDate.setTime(11, 30, using: calendar),
            durationMinutes: 30,
            status: .scheduled
        )
        let availability = AppointmentAvailability(
            searchDate: selectedDate,
            appointments: [existingAppointment],
            calendar: calendar
        )

        #expect(
            !availability.canPrefill(
                start: selectedDate.setTime(11, 0, using: calendar),
                durationMinutes: 45
            )
        )
    }

    @Test func breakCrossingStartIsNotUsedForPrefill() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let availability = AppointmentAvailability(
            searchDate: selectedDate,
            appointments: [],
            calendar: calendar
        )

        #expect(
            !availability.canPrefill(
                start: selectedDate.setTime(12, 30, using: calendar),
                durationMinutes: 60
            )
        )
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
