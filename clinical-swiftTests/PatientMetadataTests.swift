import Foundation
import Testing

@testable import clinical_swift

struct PatientMetadataTests {
    @Test func buildsNamedPatientMetadataWithoutCreatedDateFallback() {
        let calendar = fixedCalendar()
        let referenceDate = #require(calendar.date(2026, 6, 10))
        let dob = #require(calendar.date(1990, 6, 10))
        let createdDate = #require(calendar.date(2026, 5, 28))
        let patient = Patient(
            name: "Aarav Mehta",
            dob: dob,
            gender: .male,
            nextAppointmentDate: nil,
            createdDate: createdDate
        )

        let metadata = PatientMetadata.metadata(
            for: patient,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX")
        )

        #expect(metadata.parts == ["36y/M"])
        #expect(metadata.subtitle == "36y/M")
    }

    @Test func unknownPatientUsesCreatedDateWhenNextAppointmentIsMissing() {
        let calendar = fixedCalendar()
        let referenceDate = #require(calendar.date(2026, 6, 10))
        let dob = #require(calendar.date(1990, 6, 10))
        let createdDate = #require(calendar.date(2026, 5, 28))
        let patient = Patient(
            name: nil,
            phone: "+91 98201 44532",
            dob: dob,
            gender: .female,
            nextAppointmentDate: nil,
            createdDate: createdDate
        )

        let metadata = PatientMetadata.metadata(
            for: patient,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX")
        )

        #expect(metadata.parts.count == 3)
        #expect(metadata.parts[0] == "36y/F")
        #expect(metadata.parts[1] == "+91 98201 44532")
        #expect(metadata.parts[2].hasPrefix("Created"))
    }

    @Test func nextAppointmentTakesPriorityOverUnknownCreatedDate() {
        let calendar = fixedCalendar()
        let referenceDate = #require(calendar.date(2026, 6, 10))
        let nextAppointment = #require(calendar.date(2026, 6, 11, hour: 18))
        let createdDate = #require(calendar.date(2026, 5, 28))
        let patient = Patient(
            name: nil,
            phone: "+91 98201 44532",
            nextAppointmentDate: nextAppointment,
            createdDate: createdDate
        )

        let metadata = PatientMetadata.metadata(
            for: patient,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX")
        )

        #expect(metadata.parts.count == 2)
        #expect(metadata.parts[0] == "+91 98201 44532")
        #expect(metadata.parts[1].hasPrefix("Next"))
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = #require(TimeZone(secondsFromGMT: 0))
        return calendar
    }
}
