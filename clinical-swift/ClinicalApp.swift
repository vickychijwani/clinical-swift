import SQLiteData
import SwiftUI

@main
struct ClinicalApp: App {
    init() {
        try! prepareDependencies {
            $0.defaultDatabase = try appDatabase(seedSamples: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if CommandLine.arguments.contains("--ui-testing-appointment-hitboxes") {
                    AppointmentHitboxUITestView()
                } else {
                    ContentView()
                }
            #else
                ContentView()
            #endif
        }
    }
}
