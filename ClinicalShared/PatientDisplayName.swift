import Foundation

nonisolated enum PatientDisplayName {
    static let unknown = "Unknown Patient"

    static func resolve(_ name: String?) -> String {
        guard
            let name,
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return unknown
        }
        return name
    }
}
