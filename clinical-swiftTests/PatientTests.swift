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

    @Test func normalizesProvidedNameAndPhone() {
        let patient = Patient(
            name: "  Aarav Mehta  ",
            phone: "  +91 98201 44532  "
        )

        #expect(patient.name == "Aarav Mehta")
        #expect(patient.phone == "+919820144532")
    }

    @Test func assumesIndiaForPhoneWithoutCountryCode() {
        #expect(Patient(name: nil, phone: "98201 44532").phone == "+919820144532")
        #expect(Patient(name: nil, phone: "098201 44532").phone == "+919820144532")
        #expect(Patient(name: nil, phone: "91 98201 44532").phone == "+919820144532")
    }

    @Test func preservesExplicitInternationalCountryCode() {
        #expect(Patient(name: nil, phone: "+1 (415) 555-2671").phone == "+14155552671")
        #expect(Patient(name: nil, phone: "0044 20 7946 0958").phone == "+442079460958")
    }

    @Test func formatsPhoneNumbersForDisplay() {
        #expect(PhoneNumber.formattedForDisplay("+911234567890") == "+91 12345 67890")
        #expect(PhoneNumber.formattedForDisplay("+12025550100") == "+1 202 555 0100")
        #expect(PhoneNumber.formattedForDisplay("+442079460958") == "+442079460958")
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
