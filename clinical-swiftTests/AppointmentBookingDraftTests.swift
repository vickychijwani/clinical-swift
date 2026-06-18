import Dependencies
import Foundation
import Testing
@testable import clinical_swift

struct AppointmentBookingDraftTests {
    @Test func startTimePreservesSelectedMinuteAndDropsSeconds() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let proposedTime = try Date("2026-04-21T10:03:42Z", strategy: .iso8601)

        let normalizedTime = withDependencies {
            $0.calendar = calendar
        } operation: {
            AppointmentBookingDraft(
                selectedDate: selectedDate,
                startTime: proposedTime
            )
            .startTime
        }

        let components = calendar.dateComponents([.hour, .minute, .second], from: normalizedTime)
        #expect(components.hour == 10)
        #expect(components.minute == 3)
        #expect(components.second == 0)
    }

    @Test func startTimeClampsToClinicOpening() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let proposedTime = try Date("2026-04-21T08:55:00Z", strategy: .iso8601)

        let normalizedTime = withDependencies {
            $0.calendar = calendar
        } operation: {
            AppointmentBookingDraft(
                selectedDate: selectedDate,
                startTime: proposedTime
            )
            .startTime
        }

        let components = calendar.dateComponents([.hour, .minute], from: normalizedTime)
        #expect(components.hour == 9)
        #expect(components.minute == 0)
    }

    @Test func startTimeClampsToFixedLatestStartIndependentOfDuration() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let proposedTime = try Date("2026-04-21T20:30:00Z", strategy: .iso8601)

        let normalizedTime = withDependencies {
            $0.calendar = calendar
        } operation: {
            AppointmentBookingDraft(
                selectedDate: selectedDate,
                startTime: proposedTime,
                durationMinutes: 120
            )
            .startTime
        }

        let components = calendar.dateComponents([.hour, .minute], from: normalizedTime)
        #expect(components.hour == 20)
        #expect(components.minute == 30)
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

    @Test func validationAllowsPositiveDurationToExtendPastClosing() throws {
        let calendar = gregorianCalendar
        let patient = patientItem()
        try withDependencies {
            $0.calendar = calendar
        } operation: {
            let draft = AppointmentBookingDraft(
                selectedPatient: patient,
                selectedDate: try Date("2026-04-21T00:00:00Z", strategy: .iso8601),
                durationMinutes: 800
            )

            #expect(throws: Never.self) {
                try draft.validate()
            }
        }
    }

    @Test func validationRejectsNonPositiveDuration() throws {
        let calendar = gregorianCalendar
        let patient = patientItem()
        try withDependencies {
            $0.calendar = calendar
        } operation: {
            let draft = AppointmentBookingDraft(
                selectedPatient: patient,
                selectedDate: try Date("2026-04-21T00:00:00Z", strategy: .iso8601),
                durationMinutes: 0
            )

            #expect(throws: AppointmentBookingValidationError.invalidTime) {
                try draft.validate()
            }
        }
    }

    @Test func validationAllowsStartInsideClinicBreak() throws {
        let calendar = gregorianCalendar
        let patient = patientItem()
        try withDependencies {
            $0.calendar = calendar
        } operation: {
            let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
            let draft = AppointmentBookingDraft(
                selectedPatient: patient,
                selectedDate: selectedDate,
                startTime: selectedDate.setTime(14, 0, using: calendar)
            )

            #expect(throws: Never.self) {
                try draft.validate()
            }
        }
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func patientItem() -> PatientDetails {
        PatientDetails(
            patient: Patient(name: "Aarav Mehta"),
            nextAppointmentDate: nil
        )
    }
}
