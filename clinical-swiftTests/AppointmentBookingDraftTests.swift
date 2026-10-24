import ClinicalModels
import Dependencies
import Foundation
import Testing

@testable import clinical_swift

struct AppointmentBookingDraftTests {
    @Test func startPreservesSelectedMinuteAndDropsSeconds() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let proposedTime = try Date("2026-04-21T10:03:42Z", strategy: .iso8601)

        let normalizedTime = withDependencies {
            $0.calendar = calendar
        } operation: {
            AppointmentBookingDraft(
                selectedDate: selectedDate,
                start: proposedTime
            )
            .start
        }

        let components = calendar.dateComponents([.hour, .minute, .second], from: normalizedTime)
        #expect(components.hour == 10)
        #expect(components.minute == 3)
        #expect(components.second == 0)
    }

    @Test func startClampsToClinicOpening() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let proposedTime = try Date("2026-04-21T08:55:00Z", strategy: .iso8601)

        let normalizedTime = withDependencies {
            $0.calendar = calendar
        } operation: {
            AppointmentBookingDraft(
                selectedDate: selectedDate,
                start: proposedTime
            )
            .start
        }

        let components = calendar.dateComponents([.hour, .minute], from: normalizedTime)
        #expect(components.hour == 9)
        #expect(components.minute == 0)
    }

    @Test func startClampsSoDurationEndsByClosing() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let proposedTime = try Date("2026-04-21T20:30:00Z", strategy: .iso8601)

        let normalizedTime = withDependencies {
            $0.calendar = calendar
        } operation: {
            AppointmentBookingDraft(
                selectedDate: selectedDate,
                start: proposedTime,
                durationMinutes: 120
            )
            .start
        }

        let components = calendar.dateComponents([.hour, .minute], from: normalizedTime)
        #expect(components.hour == 19)
        #expect(components.minute == 0)
    }

    @Test func validationRequiresPatient() throws {
        let calendar = gregorianCalendar
        try withDependencies {
            $0.calendar = calendar
        } operation: {
            let draft = AppointmentBookingDraft(
                selectedDate: try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
            )

            #expect(throws: AppointmentBookingValidationError.missingPatient) {
                try draft.validate()
            }
        }
    }

    @Test func validationRejectsDurationThatCannotFitClinicHours() throws {
        let calendar = gregorianCalendar
        let patient = Patient(name: "Aarav Mehta")
        try withDependencies {
            $0.calendar = calendar
        } operation: {
            let draft = AppointmentBookingDraft(
                selectedPatient: patient,
                selectedDate: try Date("2026-04-21T00:00:00Z", strategy: .iso8601),
                durationMinutes: 800
            )

            #expect(throws: AppointmentBookingValidationError.invalidTime) {
                try draft.validate()
            }
        }
    }

    @Test func validationAllowsAppointmentAcrossBreak() throws {
        let calendar = gregorianCalendar
        let patient = Patient(name: "Aarav Mehta")
        try withDependencies {
            $0.calendar = calendar
        } operation: {
            let selectedDate = try Date(
                "2026-04-21T00:00:00Z",
                strategy: .iso8601
            )
            let draft = AppointmentBookingDraft(
                selectedPatient: patient,
                selectedDate: selectedDate,
                start: selectedDate.setTime(12, 30, using: calendar),
                durationMinutes: 60
            )

            try draft.validate()
        }
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

}
