import Foundation

public nonisolated enum PatientDisplayName {
    public static let unknown = "Unknown Patient"

    public static func resolve(_ name: String?) -> String {
        guard
            let name,
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return unknown
        }
        return name
    }
}
