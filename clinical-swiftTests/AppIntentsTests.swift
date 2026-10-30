import AppIntents
import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct AppIntentsTests {
    @Test func bookingURLRequiresTheExactSafeRoute() throws {
        #expect(
            ClinicalURL(try #require(URL(string: "clinical://appointments/book")))
                == .bookAppointment
        )
        #expect(ClinicalURL(try #require(URL(string: "CLINICAL://APPOINTMENTS/book"))) != nil)
        #expect(
            ClinicalURL(try #require(URL(string: "clinical://appointments/book?patient=1"))) == nil)
        #expect(ClinicalURL(try #require(URL(string: "clinical://appointments/delete"))) == nil)
        #expect(ClinicalURL(try #require(URL(string: "https://appointments/book"))) == nil)
    }

    @Test func widgetURLsRoundTripAndRejectMalformedDestinations() throws {
        let appointmentID = UUID()
        let appointmentURL = try #require(ClinicalURL.appointment(appointmentID).url)
        #expect(ClinicalURL(appointmentURL) == .appointment(appointmentID))

        let day = try #require(ScheduleDay(year: 2026, month: 7, day: 13))
        let scheduleURL = try #require(ClinicalURL.schedule(day).url)
        #expect(scheduleURL.absoluteString == "clinical://schedule?date=2026-07-13")
        #expect(ClinicalURL(scheduleURL) == .schedule(day))

        #expect(ClinicalURL(try #require(URL(string: "clinical://appointments/not-a-uuid"))) == nil)
        #expect(
            ClinicalURL(try #require(URL(string: "clinical://schedule?date=2026-02-30"))) == nil)
        #expect(
            ClinicalURL(
                try #require(URL(string: "clinical://schedule?date=2026-07-13&extra=1"))
            ) == nil
        )
    }

    @Test func contactPhonesIncludePrimaryAndAliasesAndDiscardOtherHandles() {
        let person = IntentPerson(
            identifier: .contact("contact-id"),
            name: .displayName("Aarav Mehta"),
            handle: IntentPerson.Handle(phoneNumber: "98201 44532"),
            aliases: [
                IntentPerson.Handle(phoneNumber: "+91 98201 44532"),
                IntentPerson.Handle(phoneNumber: "022 1234 5678"),
                IntentPerson.Handle(emailAddress: "aarav@example.com"),
            ]
        )

        #expect(
            FindPatientFromContactIntent.phoneNumbers(from: person)
                == ["+919820144532", "+912212345678"]
        )
    }

    @Test func contactMatchingRoutesOnePatientToDetailsAndManyToPhoneSearch() async throws {
        let database = try testDatabase()
        let createdDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let first = Patient(
            name: "Aarav Mehta",
            phone: "+91 98201 44532",
            createdDate: createdDate
        )
        let second = Patient(
            name: "Mira Mehta",
            phone: "98201 44532",
            createdDate: createdDate
        )
        let third = Patient(
            name: "Ishaan Shah",
            phone: "98201 44533",
            createdDate: createdDate
        )

        try await database.write { db in
            for patient in [first, second, third] {
                try PatientRecord.insert { PatientRecord(patient) }.execute(db)
            }
        }

        let router = makeRouter()
        let actions = ClinicalAppActions(router: router, database: database)

        let singleMatch = try await actions.findPatient(phoneNumbers: ["98201 44533"])
        #expect(singleMatch == .one(third))
        #expect(router.detailsPresentation?.root == .patient(third.id))

        let multipleMatch = try await actions.findPatient(phoneNumbers: ["98201 44532"])
        #expect(multipleMatch == .multiple(2))
        #expect(router.selectedTab == .patients)
        #expect(router.detailsPresentation == nil)
        #expect(router.patientSearchRequest?.phoneNumbers == ["+919820144532"])

        let noMatch = try await actions.findPatient(phoneNumbers: ["98201 44534"])
        #expect(noMatch == .none)
    }

    private func makeRouter() -> Router {
        withDependencies {
            $0.calendar = Calendar(identifier: .gregorian)
        } operation: {
            Router()
        }
    }
}
