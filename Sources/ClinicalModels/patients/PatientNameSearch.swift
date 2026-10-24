import Foundation

public nonisolated enum PatientNameSearch {
    public static func matches(
        _ name: String?,
        searchText: String,
        locale: Locale = .autoupdatingCurrent
    ) -> Bool {
        let queryWords = words(in: searchText)
        guard !queryWords.isEmpty else {
            return true
        }

        guard let name else {
            return false
        }

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
}
