import AppIntents
import GRDB
import SQLiteData
import SwiftUI

@main
struct ClinicalApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router: Router
    private let widgetTimelineInvalidator: WidgetTimelineInvalidator

    init() {
        let router = Router()
        let database: any DatabaseWriter = try! prepareDependencies {
            let database = try appDatabase(seedSamples: true)
            $0.defaultDatabase = database
            return database
        }

        _router = State(initialValue: router)
        widgetTimelineInvalidator = WidgetTimelineInvalidator(database: database)
        AppDependencyManager.shared.add(
            dependency: ClinicalAppActions(router: router, database: database)
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
            .onChange(of: scenePhase) { _, scenePhase in
                // The live writer opts into these notifications in
                // ClinicalSharedDatabase.openWriter.
                // TODO: Revisit this when building iPad/Mac support
                // scenePhase does not necessarily indicate whole-app state when there are multiple
                // windows - scene B could suspend even though scene A still needs the database
                switch scenePhase {
                case .active:
                    NotificationCenter.default.post(
                        name: Database.resumeNotification,
                        object: nil
                    )
                case .background:
                    NotificationCenter.default.post(
                        name: Database.suspendNotification,
                        object: nil
                    )
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
}
