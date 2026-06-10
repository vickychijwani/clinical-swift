import Foundation
import Testing
@testable import clinical_swift

struct PatientSectionTests {
    @Test func groupsUnknownPatientsUnderHashBeforeAlphabeticalSections() throws {
        let patients = try [
            patient(name: "Dev Malhotra"),
            unknownPatient(createdDate: date(2026, 5, 28, hour: 17)),
            patient(name: "Aarav Mehta"),
            patient(name: "Anjali Desai"),
        ]

        let sections = PatientSection.sections(
            from: patients,
            locale: Locale(identifier: "en_US_POSIX")
        )

        #expect(sections.map(\.id) == ["#", "A", "D"])
        #expect(sections[0].patients.first?.displayName == "Unknown Patient")
        #expect(sections[1].patients.map(\.name) == ["Aarav Mehta", "Anjali Desai"])
    }

    @Test func omitsEmptySections() throws {
        let patients = try [
            patient(name: "Aarav Mehta"),
            patient(name: "Dev Malhotra"),
        ]

        let sections = PatientSection.sections(from: patients)

        #expect(sections.map(\.id) == ["A", "D"])
    }

    @Test func searchMatchesRealNamesOnly() throws {
        let patients = try [
            unknownPatient(createdDate: date(2026, 5, 28)),
            patient(name: "Unknown Roy"),
            patient(name: "Aarav Mehta"),
        ]

        let unknownSearch = PatientSection.sections(
            from: patients,
            searchText: "Unknown"
        )
        let aaravSearch = PatientSection.sections(
            from: patients,
            searchText: "aarav"
        )

        #expect(unknownSearch.flatMap(\.patients).map(\.name) == ["Unknown Roy"])
        #expect(aaravSearch.flatMap(\.patients).map(\.name) == ["Aarav Mehta"])
    }

    @Test func searchCanRemoveUnknownSection() throws {
        let patients = try [
            unknownPatient(createdDate: date(2026, 5, 28)),
            patient(name: "Aarav Mehta"),
        ]

        let sections = PatientSection.sections(
            from: patients,
            searchText: "Aarav"
        )

        #expect(sections.map(\.id) == ["A"])
    }

    @Test func searchMatchesPrefixesOfNameWordsOnly() throws {
        let patients = try [
            patient(name: "Aarav Mehta"),
            patient(name: "Ishaan Puri"),
        ]

        let sections = PatientSection.sections(
            from: patients,
            searchText: "aa"
        )

        #expect(sections.flatMap(\.patients).map(\.name) == ["Aarav Mehta"])
    }

    @Test func searchMatchesWordPrefixesInAnyOrder() throws {
        let patients = try [
            patient(name: "Aarav Mehta"),
            patient(name: "Mehta Aarav"),
            patient(name: "Mehul Arora"),
        ]

        let sections = PatientSection.sections(
            from: patients,
            searchText: "me aa"
        )

        #expect(sections.flatMap(\.patients).map(\.name) == [
            "Aarav Mehta",
            "Mehta Aarav",
        ])
    }

    private func patient(name: String) throws -> Patient {
        try Patient(name: name)
    }

    private func unknownPatient(createdDate: Date) throws -> Patient {
        try Patient(
            name: nil,
            phone: "+91 98201 44532",
            createdDate: createdDate
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return try #require(calendar.date(year, month, day, hour: hour))
    }
}
