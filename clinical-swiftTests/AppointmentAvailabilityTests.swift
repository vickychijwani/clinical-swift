import ClinicalModels
import Foundation
import Testing

@testable import clinical_swift

struct AppointmentAvailabilityTests {
    @Test func initialSuggestionUsesPreferredAutomaticStart() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let availability = AppointmentAvailability(
            searchDate: selectedDate,
            appointments: [],
            calendar: calendar
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
            availability.firstAvailableSlot(
                neededDurationMinutes: 45,
                earliestStart: selectedDate.setTime(11, 0, using: calendar)
            ) == selectedDate.setTime(12, 0, using: calendar)
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
            availability.firstAvailableSlot(
                neededDurationMinutes: 60,
                earliestStart: selectedDate.setTime(12, 30, using: calendar)
            ) == Bitehaus.break.end.on(date: selectedDate, using: calendar)
        )
    }

    @Test(arguments: [
        ("2026-04-20T15:30:00Z", "2026-04-21T00:00:00Z"),  // Monday -> Tuesday
        ("2026-04-24T22:45:00Z", "2026-04-25T00:00:00Z"),  // Friday -> Saturday
        ("2026-04-25T10:00:00Z", "2026-04-27T00:00:00Z"),  // Saturday -> Monday (skips Sunday)
        ("2026-04-26T10:00:00Z", "2026-04-27T00:00:00Z"),  // Sunday -> Monday
    ])
    func nextBusinessDayAdvancesAndSkipsSunday(base: String, expected: String) throws {
        let calendar = gregorianCalendar
        let baseDate = try Date(base, strategy: .iso8601)
        let expectedDate = try Date(expected, strategy: .iso8601)

        #expect(Bitehaus.nextBusinessDay(after: baseDate, using: calendar) == expectedDate)
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
