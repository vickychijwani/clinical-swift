import AppIntents
import SQLiteData
import SwiftUI

@main
struct ClinicalApp: App {
    @State private var router: Router

    init() {
        let router = Router()
        let database: any DatabaseWriter = try! prepareDependencies {
            let database = try appDatabase(seedSamples: true)
            $0.defaultDatabase = database
            return database
        }

        _router = State(initialValue: router)
        AppDependencyManager.shared.add(
            dependency: ClinicalAppActions(router: router, database: database)
        )
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if CommandLine.arguments.contains("--ui-testing-appointment-hitboxes") {
                    AppointmentHitboxUITestView()
                } else {
                    ContentView(router: router)
                }
            #else
                ContentView(router: router)
            #endif
        }
    }
}
