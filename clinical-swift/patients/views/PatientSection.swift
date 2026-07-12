import Foundation

struct PatientSection: Identifiable, Hashable {
    static let unknownID = "#"

    let id: String
    let items: [PatientDetails]

    static func sections(
        from items: [PatientDetails],
        searchText: String = "",
        matchingPhoneNumbers: Set<String>? = nil
    ) -> [PatientSection] {
        let locale = Locale.autoupdatingCurrent
        let filteredItems = items.filter { item in
            if let matchingPhoneNumbers {
                guard let phone = item.patient.phone else { return false }
                return matchingPhoneNumbers.contains(phone)
            }

            return PatientNameSearch.matches(
                item.patient.name,
                searchText: searchText,
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

    private static func sortedItems(_ items: [PatientDetails]) -> [PatientDetails] {
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
