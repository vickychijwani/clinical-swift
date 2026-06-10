import Foundation
import Testing
@testable import clinical_swift

struct PatientMetadataTests {
    @Test func buildsNamedPatientMetadataWithoutCreatedDateFallback() throws {
        let calendar = try fixedCalendar()
        let referenceDate = try #require(calendar.date(2026, 6, 10))
        let dob = try #require(calendar.date(1990, 6, 10))
        let createdDate = try #require(calendar.date(2026, 5, 28))
        let patient = try Patient(
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

    @Test func unknownPatientUsesCreatedDateWhenNextAppointmentIsMissing() throws {
        let calendar = try fixedCalendar()
        let referenceDate = try #require(calendar.date(2026, 6, 10))
        let dob = try #require(calendar.date(1990, 6, 10))
        let createdDate = try #require(calendar.date(2026, 5, 28))
        let patient = try Patient(
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

    @Test func nextAppointmentTakesPriorityOverUnknownCreatedDate() throws {
        let calendar = try fixedCalendar()
        let referenceDate = try #require(calendar.date(2026, 6, 10))
        let nextAppointment = try #require(calendar.date(2026, 6, 11, hour: 18))
        let createdDate = try #require(calendar.date(2026, 5, 28))
        let patient = try Patient(
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

    private func fixedCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return calendar
    }
}
