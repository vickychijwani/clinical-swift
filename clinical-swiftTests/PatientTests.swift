import Foundation
import Testing
@testable import clinical_swift

struct PatientTests {
    @Test func requiresNameOrPhone() throws {
        _ = try Patient(name: "Aarav Mehta")
        _ = try Patient(name: nil, phone: "+91 98201 44532")

        #expect(throws: Patient.ValidationError.missingNameAndPhone) {
            try Patient(name: "   ", phone: nil)
        }
        #expect(throws: Patient.ValidationError.missingNameAndPhone) {
            try Patient(name: nil, phone: "   ")
        }
        #expect(throws: Patient.ValidationError.missingNameAndPhone) {
            try Patient(name: nil, phone: nil)
        }
    }

    @Test func trimsProvidedNameAndPhone() throws {
        let patient = try Patient(
            name: "  Aarav Mehta  ",
            phone: "  +91 98201 44532  "
        )

        #expect(patient.name == "Aarav Mehta")
        #expect(patient.phone == "+91 98201 44532")
    }

    @Test func displayNameFallsBackForUnknownPatients() throws {
        let patient = try Patient(
            name: nil,
            phone: "+91 98201 44532"
        )

        #expect(patient.displayName == "Unknown Patient")
        #expect(patient.isUnknown)
    }

    @Test func derivesAgeFromDateOfBirth() throws {
        let calendar = try fixedCalendar()
        let referenceDate = try #require(calendar.date(2026, 6, 10))
        let birthdayToday = try #require(calendar.date(1990, 6, 10))
        let birthdayTomorrow = try #require(calendar.date(1990, 6, 11))
        let futureDateOfBirth = try #require(calendar.date(2027, 6, 10))

        let turnsThirtySix = try Patient(
            name: "Patient One",
            dob: birthdayToday
        )
        let stillThirtyFive = try Patient(
            name: "Patient Two",
            dob: birthdayTomorrow
        )
        let futurePatient = try Patient(
            name: "Patient Three",
            dob: futureDateOfBirth
        )

        #expect(turnsThirtySix.age(on: referenceDate, calendar: calendar) == 36)
        #expect(stillThirtyFive.age(on: referenceDate, calendar: calendar) == 35)
        #expect(futurePatient.age(on: referenceDate, calendar: calendar) == nil)
    }

    private func fixedCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return calendar
    }
}
