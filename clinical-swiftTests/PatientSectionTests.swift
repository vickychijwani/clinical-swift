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

    @Test func searchMatchesRealNamesOnly() {
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
            searchText: "aarav"
        )

        #expect(unknownSearch.flatMap(\.items).map(\.patient.name) == ["Unknown Roy"])
        #expect(aaravSearch.flatMap(\.items).map(\.patient.name) == ["Aarav Mehta"])
    }

    @Test func searchCanRemoveUnknownSection() {
        let items = [
            unknownPatient(createdDate: date(2026, 5, 28)),
            patient(name: "Aarav Mehta"),
        ]

        let sections = PatientSection.sections(
            from: items,
            searchText: "Aarav"
        )

        #expect(sections.map(\.id) == ["A"])
    }

    @Test func searchMatchesPrefixesOfNameWordsOnly() {
        let items = [
            patient(name: "Aarav Mehta"),
            patient(name: "Ishaan Puri"),
        ]

        let sections = PatientSection.sections(
            from: items,
            searchText: "aa"
        )

        #expect(sections.flatMap(\.items).map(\.patient.name) == ["Aarav Mehta"])
    }

    @Test func searchMatchesWordPrefixesInAnyOrder() {
        let items = [
            patient(name: "Aarav Mehta"),
            patient(name: "Mehta Aarav"),
            patient(name: "Mehul Arora"),
        ]

        let sections = PatientSection.sections(
            from: items,
            searchText: "me aa"
        )

        #expect(
            sections.flatMap(\.items).map(\.patient.name) == [
                "Aarav Mehta",
                "Mehta Aarav",
            ])
    }

    private func patient(name: String) -> PatientDetails {
        PatientDetails(patient: Patient(name: name), nextAppointmentDate: nil)
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
