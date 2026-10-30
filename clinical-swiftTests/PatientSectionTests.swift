import ClinicalModels
import Foundation
import Testing

@testable import clinical_swift

struct PatientSectionTests {
    @Test func groupsUnknownPatientsUnderHashBeforeAlphabeticalSections() {
        let items = [
            patient(name: "Dev Malhotra"),
            unknownPatient(createdDate: date(2026, 5, 28, hour: 17)),
            patient(name: "Aarav Mehta"),
            patient(name: "Anjali Desai"),
        ]

        let sections = PatientSection.sections(
            from: items
        )

        #expect(sections.map(\.id) == ["#", "A", "D"])
        #expect(sections[0].items.first?.patient.displayName == "Unknown Patient")
        #expect(sections[1].items.map(\.patient.name) == ["Aarav Mehta", "Anjali Desai"])
    }

    @Test func omitsEmptySections() {
        let items = [
            patient(name: "Aarav Mehta"),
            patient(name: "Dev Malhotra"),
        ]

        let sections = PatientSection.sections(from: items)

        #expect(sections.map(\.id) == ["A", "D"])
    }

    @Test func nameSearchFiltersPatientsAndOmitsEmptySections() {
        let items = [
            unknownPatient(createdDate: date(2026, 5, 28)),
            patient(name: "Unknown Roy"),
            patient(name: "Aarav Mehta"),
        ]

        let unknownSearch = PatientSection.sections(
            from: items,
            searchText: "Unknown"
        )
        let aaravSearch = PatientSection.sections(
            from: items,
            searchText: "me aa"
        )

        #expect(unknownSearch.map(\.id) == ["U"])
        #expect(aaravSearch.map(\.id) == ["A"])
        #expect(unknownSearch.flatMap(\.items).map(\.patient.name) == ["Unknown Roy"])
        #expect(aaravSearch.flatMap(\.items).map(\.patient.name) == ["Aarav Mehta"])
    }

    @Test func externalPhoneFilterMatchesEverySuppliedNumberExactly() {
        let first = patient(name: "Aarav Mehta", phone: "98201 44532")
        let second = patient(name: "Mira Shah", phone: "+91 98201 44533")
        let unrelated = patient(name: "Ishaan Puri", phone: "98201 44534")

        let sections = PatientSection.sections(
            from: [first, second, unrelated],
            searchText: "+91 98201 44532, +91 98201 44533",
            matchingPhoneNumbers: ["+919820144532", "+919820144533"]
        )

        #expect(
            sections.flatMap(\.items).map(\.patient.name) == [
                "Aarav Mehta",
                "Mira Shah",
            ]
        )
    }

    private func patient(name: String, phone: String? = nil) -> PatientDetails {
        PatientDetails(patient: Patient(name: name, phone: phone), nextAppointmentDate: nil)
    }

    private func unknownPatient(createdDate: Date) -> PatientDetails {
        PatientDetails(
            patient: Patient(
                name: nil,
                phone: "+91 98201 44532",
                createdDate: createdDate
            ),
            nextAppointmentDate: nil
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar.date(year, month, day, hour: hour)
            ?? Date(timeIntervalSinceReferenceDate: 0)
    }
}
