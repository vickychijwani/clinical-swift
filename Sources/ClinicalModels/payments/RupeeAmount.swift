import Foundation

public nonisolated enum RupeeAmount {
    /// Parsing is strict so invalid pasted text cannot become a different payment or No Dues.
    public static func parse(_ text: String, emptyAsZero: Bool = false) -> Int? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("₹") {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
        }
        if value.isEmpty { return emptyAsZero ? 0 : nil }
        let groups = value.split(separator: ",", omittingEmptySubsequences: false)
        guard groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(isDigit) }) else { return nil }
        if groups.count > 1 {
            guard groups.last?.count == 3,
                (1...2).contains(groups[0].count),
                groups.dropFirst().dropLast().allSatisfy({ $0.count == 2 })
            else { return nil }
        }
        return Int(groups.joined())
    }

    public static func formatted(_ amount: Int) -> String {
        amount.formatted(.number.locale(ClinicDate.locale).grouping(.automatic))
    }

    public static func isDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }
}
