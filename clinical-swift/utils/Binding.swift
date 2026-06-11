import SwiftUI

extension Binding where Value == String? {
    /// Bridges an optional String binding into a non-optional String binding with a fallback default.
    func replacingNil(with fallback: String = "") -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? fallback },
            set: { self.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

extension Binding where Value == Date? {
    /// Bridges an optional Date binding into a non-optional Date binding with a fallback default.
    func replacingNil(with fallback: Date = .now) -> Binding<Date> {
        Binding<Date>(
            get: { self.wrappedValue ?? fallback },
            set: { self.wrappedValue = $0 }
        )
    }
}
