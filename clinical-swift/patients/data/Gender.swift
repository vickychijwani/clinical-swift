import Foundation

nonisolated enum Gender: Hashable, Sendable {
    case female
    case male
    case other

    var displayName: String {
        switch self {
        case .female:
            "F"
        case .male:
            "M"
        case .other:
            "Other"
        }
    }
}
