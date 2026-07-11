import Dependencies
import Foundation
import Testing

@testable import clinical_swift

struct AppointmentMessageFormatterTests {
    @Test func confirmationIncludesExactTemplateFields() throws {
        let calendar = fixedCalendar
        let start = try Date("2026-03-04T18:30:00Z", strategy: .iso8601)
        let details = appointmentDetails(
            patientName: "Aarav Mehta",
            patientGender: .male,
            start: start
        )

        let message = AppointmentMessageFormatter(
            kind: .confirmation,
            details: details,
            includesLocation: true,
            now: try Date("2026-03-03T09:00:00Z", strategy: .iso8601),
            calendar: calendar
        )
        .message()

        #expect(
            message
                == """
                Hello Mr. Aarav,

                Your appointment with Dr. Monica Mulchandani at Bitehaus Dental Clinic is confirmed on Wed, 4 Mar at 6:30 PM.

                Location: https://maps.app.goo.gl/M3cuCEojHWQQ1NkC7

                Best Regards 🙏
                """
        )
    }

    @Test func reminderUsesTodayClauseAndNoLocationWhenNotFirstScheduledAppointment() throws {
        let calendar = fixedCalendar
        let start = try Date("2026-03-04T18:00:00Z", strategy: .iso8601)
        let details = appointmentDetails(
            patientName: "Anjali Desai",
            patientGender: .female,
            start: start
        )

        let message = AppointmentMessageFormatter(
            kind: .reminder,
            details: details,
            includesLocation: false,
            now: try Date("2026-03-04T09:00:00Z", strategy: .iso8601),
            calendar: calendar
        )
        .message()

        #expect(
            message
                == """
                Hello Ms. Anjali,

                This is a gentle reminder that you have an appointment with Dr. Monica Mulchandani at Bitehaus Dental Clinic for today at 6:00 PM.

                Best Regards 🙏
                """
        )
    }

    @Test func missingPatientNameUsesPlainGreeting() throws {
        let calendar = fixedCalendar
        let start = try Date("2026-03-04T18:00:00Z", strategy: .iso8601)
        let namelessDetails = appointmentDetails(patientName: nil, start: start)

        let namelessMessage = AppointmentMessageFormatter(
            kind: .confirmation,
            details: namelessDetails,
            includesLocation: false,
            now: start,
            calendar: calendar
        )
        .message()

        #expect(namelessMessage.hasPrefix("Hello,\n\nYour appointment"))
    }

    @Test func otherOrMissingGenderOmitsHonorific() throws {
        let start = try Date("2026-03-04T18:00:00Z", strategy: .iso8601)

        for gender in [Gender.other, nil] {
            let details = appointmentDetails(
                patientName: "Sam Shah",
                patientGender: gender,
                start: start
            )
            let message = AppointmentMessageFormatter(
                kind: .confirmation,
                details: details,
                includesLocation: false,
                now: start,
                calendar: fixedCalendar
            )
            .message()

            #expect(message.hasPrefix("Hello Sam,\n\nYour appointment"))
        }
    }

    private func appointmentDetails(
        patientName: String?,
        patientGender: Gender? = nil,
        start: Date
    ) -> AppointmentDetails {
        let patient = Patient(
            name: patientName,
            phone: "+91 98201 44532",
            gender: patientGender,
            createdDate: start
        )
        return AppointmentDetails(
            appointment: Appointment(
                patientName: patient.displayName,
                start: start,
                durationMinutes: 30,
                status: .scheduled
            ),
            patient: patient
        )
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_IN")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }
}
