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
            start: start
        )

        let message = AppointmentMessageFormatter(
            kind: .confirmation,
            details: details,
            includesPatientName: true,
            includesLocation: true,
            now: try Date("2026-03-03T09:00:00Z", strategy: .iso8601),
            calendar: calendar
        )
        .message()

        #expect(
            message
                == """
                Hello Aarav,

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
            start: start
        )

        let message = AppointmentMessageFormatter(
            kind: .reminder,
            details: details,
            includesPatientName: true,
            includesLocation: false,
            now: try Date("2026-03-04T09:00:00Z", strategy: .iso8601),
            calendar: calendar
        )
        .message()

        #expect(
            message
                == """
                Hello Anjali,

                This is a gentle reminder that you have an appointment with Dr. Monica Mulchandani at Bitehaus Dental Clinic for today at 6:00 PM.

                Best Regards 🙏
                """
        )
    }

    @Test func disabledOrMissingPatientNameUsesPlainGreeting() throws {
        let calendar = fixedCalendar
        let start = try Date("2026-03-04T18:00:00Z", strategy: .iso8601)
        let namedDetails = appointmentDetails(patientName: "Dev Malhotra", start: start)
        let namelessDetails = appointmentDetails(patientName: nil, start: start)

        let disabledNameMessage = AppointmentMessageFormatter(
            kind: .confirmation,
            details: namedDetails,
            includesPatientName: false,
            includesLocation: false,
            now: start,
            calendar: calendar
        )
        .message()
        let namelessMessage = AppointmentMessageFormatter(
            kind: .confirmation,
            details: namelessDetails,
            includesPatientName: true,
            includesLocation: false,
            now: start,
            calendar: calendar
        )
        .message()

        #expect(disabledNameMessage.hasPrefix("Hello,\n\nYour appointment"))
        #expect(namelessMessage.hasPrefix("Hello,\n\nYour appointment"))
    }

    private func appointmentDetails(
        patientName: String?,
        start: Date
    ) -> AppointmentDetails {
        let patient = Patient(
            name: patientName,
            phone: "+91 98201 44532",
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
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }
}
