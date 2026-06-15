import Foundation

struct PatientSection: Identifiable, Hashable {
    static let unknownID = "#"

    let id: String
    let items: [PatientListItem]

    static func sections(
        from items: [PatientListItem],
        searchText: String = ""
    ) -> [PatientSection] {
        let locale = Locale.autoupdatingCurrent
        let queryWords = words(in: searchText)
        let filteredItems = items.filter { item in
            guard !queryWords.isEmpty else {
                return true
            }

            guard let name = item.patient.name else {
                return false
            }

            return nameMatchesSearch(
                name,
                queryWords: queryWords,
                locale: locale
            )
        }

        let groupedItems = Dictionary(grouping: filteredItems) { item in
            sectionID(for: item.patient, locale: locale)
        }

        return groupedItems.keys
            .sorted(by: sectionIDSort)
            .compactMap { sectionID in
                guard let items = groupedItems[sectionID], !items.isEmpty else {
                    return nil
                }

                return PatientSection(
                    id: sectionID,
                    items: sortedItems(items)
                )
            }
    }

    private static func nameMatchesSearch(
        _ name: String,
        queryWords: [String],
        locale: Locale
    ) -> Bool {
        let nameWords = words(in: name)

        return queryWords.allSatisfy { queryWord in
            nameWords.contains { nameWord in
                nameWord.range(
                    of: queryWord,
                    options: [.anchored, .caseInsensitive, .diacriticInsensitive],
                    locale: locale
                ) != nil
            }
        }
    }

    private static func words(in text: String) -> [String] {
        text.split { character in
            !character.isLetter && !character.isNumber
        }
        .map(String.init)
    }

    private static func sectionID(for patient: Patient, locale: Locale) -> String {
        guard let name = patient.name else {
            return unknownID
        }

        let firstCharacter = String(name.prefix(1)).uppercased(with: locale)

        guard firstCharacter.rangeOfCharacter(from: .letters) != nil else {
            return unknownID
        }

        return firstCharacter
    }

    private static func sectionIDSort(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == unknownID {
            return rhs != unknownID
        }

        if rhs == unknownID {
            return false
        }

        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private static func sortedItems(_ items: [PatientListItem]) -> [PatientListItem] {
        items.sorted { lhs, rhs in
            switch (lhs.patient.name, rhs.patient.name) {
            case (nil, nil):
                return lhs.patient.createdDate < rhs.patient.createdDate
            case (nil, _):
                return true
            case (_, nil):
                return false
            case (.some(let lhsName), .some(let rhsName)):
                return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
            }
        }
    }
}
