import Foundation

nonisolated enum PhoneNumber {
    static func normalizedE164(_ value: String?) -> String? {
        guard let value = value?.nilIfBlank else { return nil }

        let digits = value.filter { $0.isASCII && $0.isNumber }

        guard !digits.isEmpty else { return nil }

        let internationalDigits: String
        if value.starts(with: "+") {
            internationalDigits = digits
        } else if digits.hasPrefix("00") {
            internationalDigits = String(digits.dropFirst(2))
        } else if digits.count == 12, digits.hasPrefix("91") {
            internationalDigits = digits
        } else {
            // Indian contacts may include the domestic trunk prefix instead of a country code.
            let indianNationalNumber =
                digits.count == 11 && digits.hasPrefix("0")
                ? String(digits.dropFirst())
                : digits
            internationalDigits = "91\(indianNationalNumber)"
        }

        guard let firstDigit = internationalDigits.first else { return nil }
        guard firstDigit != "0", (1...15).contains(internationalDigits.count) else { return nil }

        return "+\(internationalDigits)"
    }

    static func formattedForDisplay(_ value: String?) -> String? {
        guard let number = normalizedE164(value) else { return nil }

        if number.hasPrefix("+91"), number.count == 13 {
            let nationalNumber = number.dropFirst(3)
            return "+91 \(nationalNumber.prefix(5)) \(nationalNumber.suffix(5))"
        }

        if number.hasPrefix("+1"), number.count == 12 {
            let nationalNumber = number.dropFirst(2)
            let areaCode = nationalNumber.prefix(3)
            let centralOfficeCode = nationalNumber.dropFirst(3).prefix(3)
            let subscriberNumber = nationalNumber.suffix(4)
            return "+1 \(areaCode) \(centralOfficeCode) \(subscriberNumber)"
        }

        return number
    }
}
