import AppIntents
import GRDB
import OSLog
import SQLiteData
import SwiftUI

@main
struct ClinicalApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router: Router
    @State private var backups: BackupCoordinator?
    private let startupError: String?
    private let widgetTimelineInvalidator: WidgetTimelineInvalidator?
    private let calendarSyncCoordinator: CalendarSyncCoordinator?

    init() {
        let router = Router()
        _router = State(initialValue: router)
        let startup = AppStartup.load(router: router)
        _backups = State(initialValue: startup.backups)
        widgetTimelineInvalidator = startup.widgetTimelineInvalidator
        calendarSyncCoordinator = startup.calendarSyncCoordinator
        startupError = startup.error
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let startupError {
                    ContentUnavailableView(
                        "Data unavailable", systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(startupError))
                } else if let backups {
                    Group {
                        #if DEBUG
                            if CommandLine.arguments.contains("--ui-testing-timeline-adjustment") {
                                TimelineAdjustmentUITestView()
                            } else if CommandLine.arguments.contains(
                                "--ui-testing-appointment-hitboxes")
                            {
                                AppointmentHitboxUITestView()
                            } else {
                                ContentView(router: router)
                            }
                        #else
                            ContentView(router: router)
                        #endif
                    }
                    .environment(backups)
                } else {
                    #if INTERNAL_BACKUP_CHECK
                        if BackupCheckAuthorization.isRequested {
                            BackupCheckAuthorizationView()
                        }
                    #endif
                }
            }
            .task {
                await backups?.opportunity()
            }
            .task {
                await calendarSyncCoordinator?.activate()
            }
            .onChange(of: scenePhase) { _, scenePhase in
                guard backups != nil else { return }
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
                    backups?.isForeground = true
                    Task { await calendarSyncCoordinator?.activate() }
                    Task { await backups?.opportunity() }
                case .background:
                    backups?.isForeground = false
                    backups?.cancel()
                    backups?.scheduleBackground()
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

@MainActor
private struct AppStartup {
    var backups: BackupCoordinator?
    var widgetTimelineInvalidator: WidgetTimelineInvalidator?
    var calendarSyncCoordinator: CalendarSyncCoordinator?
    var error: String?

    static func load(router: Router) -> Self {
        #if INTERNAL_BACKUP_CHECK
            if BackupCheckAuthorization.isRequested {
                // Authentication setup must not schedule or capture a separate empty dataset.
                return Self()
            }
        #endif
        do {
            #if DEBUG
                // Keep gesture tests away from clinic data and its background integrations.
                if CommandLine.arguments.contains("--ui-testing-timeline-adjustment")
                    || CommandLine.arguments.contains("--ui-testing-color-lab")
                {
                    return try timelineAdjustmentTest()
                }
            #endif
            return try live(router: router)
        } catch {
            Logger(subsystem: "in.bitehaus.clinical", category: "Startup")
                .error("App startup failed: \(String(describing: error), privacy: .private)")
            return Self(
                error:
                    "Clinical could not open its data. Keep the app installed and contact support for assisted recovery."
            )
        }
    }

    private static func live(router: Router) throws -> Self {
        let store = BackupStateStore.live()
        let restore = try BackupRestore(
            store: store, databaseURL: ClinicalSharedDatabase.databaseURL())
        #if INTERNAL_RECOVERY
            try BackupRestoreHarness.run(restore: restore)
        #endif
        let policy = try restore.prepareForStartup()
        let database = try openDatabase(policy: policy)
        let backups = BackupCoordinator(database: database, store: store)
        if policy.allowsBackgroundBackups { backups.registerBackgroundTask() }
        let widgetTimelineInvalidator = WidgetTimelineInvalidator(database: database)
        let calendarSyncCoordinator = CalendarSyncCoordinator(
            database: database, calendarClient: .live(), contactClient: .liveValue
        )
        AppDependencyManager.shared.add(
            dependency: ClinicalAppActions(router: router, database: database)
        )
        return Self(
            backups: backups, widgetTimelineInvalidator: widgetTimelineInvalidator,
            calendarSyncCoordinator: calendarSyncCoordinator)
    }

    private static func openDatabase(policy: BackupRestore.StartupPolicy) throws
        -> any DatabaseWriter
    {
        try prepareDependencies {
            let database = try appDatabase(
                seedSamples: policy.seedSamples, recoverySafe: policy.recoverySafe)
            $0.defaultDatabase = database
            return database
        }
    }

    #if DEBUG
        private static func timelineAdjustmentTest() throws -> Self {
            let database = try prepareDependencies {
                let database = try TimelineAdjustmentUITestView.makeDatabase()
                $0.defaultDatabase = database
                return database
            }
            return Self(
                backups: BackupCoordinator(
                    database: database,
                    store: BackupStateStore(
                        directory: .temporaryDirectory.appending(path: UUID().uuidString))))
        }
    #endif
}
