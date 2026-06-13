import Foundation
import Testing
@testable import clinical_swift

struct PatientTests {
    @Test func requiresNameOrPhoneOnValidate() {
        _ = Patient(name: "Aarav Mehta")
        _ = Patient(name: nil, phone: "+91 98201 44532")
        _ = Patient(name: "   ", phone: nil)
        _ = Patient(name: nil, phone: "   ")
        _ = Patient(name: nil, phone: nil)

        #expect(throws: Patient.ValidationError.missingNameAndPhone) {
            try Patient(name: "   ", phone: nil).validate()
        }
        #expect(throws: Patient.ValidationError.missingNameAndPhone) {
            try Patient(name: nil, phone: "   ").validate()
        }
        #expect(throws: Patient.ValidationError.missingNameAndPhone) {
            try Patient(name: nil, phone: nil).validate()
        }
    }

    @Test func trimsProvidedNameAndPhone() {
        let patient = Patient(
            name: "  Aarav Mehta  ",
            phone: "  +91 98201 44532  "
        )

        #expect(patient.name == "Aarav Mehta")
        #expect(patient.phone == "+91 98201 44532")
    }

    @Test func displayNameFallsBackForUnknownPatients() {
        let patient = Patient(
            name: nil,
            phone: "+91 98201 44532"
        )

        #expect(patient.displayName == "Unknown Patient")
        #expect(patient.isUnknown)
    }

    @Test func derivesAgeFromDateOfBirth() throws {
        let calendar = fixedCalendar()
        let referenceDate = try #require(calendar.date(2026, 6, 10))
        let birthdayToday = try #require(calendar.date(1990, 6, 10))
        let birthdayTomorrow = try #require(calendar.date(1990, 6, 11))
        let futureDateOfBirth = try #require(calendar.date(2027, 6, 10))

        let turnsThirtySix = Patient(
            name: "Patient One",
            dob: birthdayToday
        )
        let stillThirtyFive = Patient(
            name: "Patient Two",
            dob: birthdayTomorrow
        )
        let futurePatient = Patient(
            name: "Patient Three",
            dob: futureDateOfBirth
        )

        #expect(turnsThirtySix.age(on: referenceDate, calendar: calendar) == 36)
        #expect(stillThirtyFive.age(on: referenceDate, calendar: calendar) == 35)
        #expect(futurePatient.age(on: referenceDate, calendar: calendar) == nil)
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }
}
