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
            ContentView()
        }
    }
}
