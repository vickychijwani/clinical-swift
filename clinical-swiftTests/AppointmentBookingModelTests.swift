import Dependencies
import Foundation
import Testing

@testable import clinical_swift

@MainActor
struct AppointmentBookingModelTests {
    @Test func dateChangePreservesAvailableClockTime() throws {
        let calendar = gregorianCalendar
        let initialDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let newDate = try Date("2026-04-22T00:00:00Z", strategy: .iso8601)

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let model = AppointmentBookingModel(selectedDate: initialDate) { _ in }
            model.selectStart(initialDate.setTime(11, 0, using: calendar))

            model.selectDate(newDate)
            model.updateAppointments([], for: newDate)

            #expect(model.draft.start == newDate.setTime(11, 0, using: calendar))
        }
    }

    @Test func dateChangeFallsBackWhenClockTimeIsUnavailable() throws {
        let calendar = gregorianCalendar
        let initialDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let newDate = try Date("2026-04-22T00:00:00Z", strategy: .iso8601)
        let existingAppointment = Appointment(
            patientName: "Aarav Mehta",
            start: newDate.setTime(11, 0, using: calendar),
            durationMinutes: 30,
            status: .scheduled
        )

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let model = AppointmentBookingModel(selectedDate: initialDate) { _ in }
            model.selectStart(initialDate.setTime(11, 0, using: calendar))

            model.selectDate(newDate)
            model.updateAppointments([existingAppointment], for: newDate)

            #expect(model.draft.start == newDate.setTime(10, 0, using: calendar))
        }
    }

    @Test func dateChangeFallsBackWhenClockTimeCrossesBreak() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let model = AppointmentBookingModel(selectedDate: selectedDate) { _ in }
            model.selectDuration(60)
            model.selectStart(selectedDate.setTime(12, 30, using: calendar))

            model.updateAppointments([], for: selectedDate)

            #expect(model.draft.start == selectedDate.setTime(10, 0, using: calendar))
        }
    }

    @Test func durationChangePreservesStartWhenAppointmentStillFits() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let existingAppointment = Appointment(
            patientName: "Aarav Mehta",
            start: selectedDate.setTime(13, 0, using: calendar),
            durationMinutes: 30,
            status: .scheduled
        )

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let model = AppointmentBookingModel(selectedDate: selectedDate) { _ in }
            model.updateAppointments([existingAppointment], for: selectedDate)
            model.selectStart(selectedDate.setTime(11, 0, using: calendar))

            model.selectDuration(60)

            #expect(model.draft.start == selectedDate.setTime(11, 0, using: calendar))
        }
    }

    @Test func availabilityFallbackRequestsDraftPreviewScroll() throws {
        let calendar = gregorianCalendar
        let initialDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let newDate = try Date("2026-04-22T00:00:00Z", strategy: .iso8601)
        let existingAppointment = Appointment(
            patientName: "Aarav Mehta",
            start: newDate.setTime(11, 0, using: calendar),
            durationMinutes: 30,
            status: .scheduled
        )

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let model = AppointmentBookingModel(selectedDate: initialDate) { _ in }
            model.selectStart(initialDate.setTime(11, 0, using: calendar))
            let scrollRequestBeforeFallback = model.draftPreviewScrollRequest

            model.selectDate(newDate)
            model.updateAppointments([existingAppointment], for: newDate)

            #expect(model.draft.start == newDate.setTime(10, 0, using: calendar))
            #expect(model.draftPreviewScrollRequest == scrollRequestBeforeFallback + 1)
        }
    }

    @Test func manualStartSelectionRequestsDraftPreviewScroll() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let model = AppointmentBookingModel(selectedDate: selectedDate) { _ in }
            #expect(model.draftPreviewScrollRequest == 0)

            model.selectStart(selectedDate.setTime(12, 0, using: calendar))

            #expect(model.draft.start == selectedDate.setTime(12, 0, using: calendar))
            #expect(model.draftPreviewScrollRequest == 1)
        }
    }

    @Test func staleAppointmentUpdateAfterDateChangeIsIgnored() throws {
        let calendar = gregorianCalendar
        let initialDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let newDate = try Date("2026-04-22T00:00:00Z", strategy: .iso8601)
        let staleAppointment = Appointment(
            patientName: "Aarav Mehta",
            start: initialDate.setTime(11, 0, using: calendar),
            durationMinutes: 30,
            status: .scheduled
        )

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let model = AppointmentBookingModel(selectedDate: initialDate) { _ in }
            model.updateAppointments([staleAppointment], for: initialDate)

            model.selectDate(newDate)
            model.updateAppointments([staleAppointment], for: initialDate)

            #expect(model.appointments.isEmpty)
            #expect(model.draft.selectedDate == newDate)
        }
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
