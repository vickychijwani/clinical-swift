import SwiftUI

nonisolated enum AppMotion {
    static let isEnabled: Bool = {
        #if DEBUG
            let arguments = CommandLine.arguments
            if arguments.contains("--ui-testing-normal-motion") {
                return true
            }
            return !arguments.contains(where: { $0.hasPrefix("--ui-testing-") })
        #else
            true
        #endif
    }()

    static func animation(_ animation: Animation) -> Animation? {
        isEnabled ? animation : nil
    }
}
