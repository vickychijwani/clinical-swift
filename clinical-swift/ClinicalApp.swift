import AppIntents
import GRDB
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
        #if INTERNAL_BACKUP_CHECK
            if BackupCheckAuthorization.isRequested {
                // Authentication setup must not schedule or capture a separate empty dataset.
                _backups = State(initialValue: nil)
                widgetTimelineInvalidator = nil
                calendarSyncCoordinator = nil
                startupError = nil
                return
            }
        #endif
        do {
            #if DEBUG
                // Keep gesture tests away from clinic data and its background integrations.
                if CommandLine.arguments.contains("--ui-testing-timeline-adjustment")
                    || CommandLine.arguments.contains("--ui-testing-color-lab")
                {
                    let database = try prepareDependencies {
                        let database = try TimelineAdjustmentUITestView.makeDatabase()
                        $0.defaultDatabase = database
                        return database
                    }
                    _backups = State(
                        initialValue: BackupCoordinator(
                            database: database,
                            store: BackupStateStore(
                                directory: .temporaryDirectory.appending(path: UUID().uuidString))))
                    widgetTimelineInvalidator = nil
                    calendarSyncCoordinator = nil
                    startupError = nil
                    return
                }
            #endif
            let store = BackupStateStore.live()
            let restore = try BackupRestore(
                store: store, databaseURL: ClinicalSharedDatabase.databaseURL())
            #if INTERNAL_RECOVERY
                try BackupRestoreHarness.run(restore: restore)
            #endif
            var hasJournal = FileManager.default.fileExists(
                atPath: restore.journalURL.path(percentEncoded: false))
            if hasJournal {
                let journal = try BackupFiles.load(
                    BackupRestoreJournal.self, from: restore.journalURL)
                if journal.phase != .rolledBack { try restore.installOrResume() }
                hasJournal = FileManager.default.fileExists(
                    atPath: restore.journalURL.path(percentEncoded: false))
            }
            let database: any DatabaseWriter = try prepareDependencies {
                let database = try appDatabase(
                    seedSamples: !hasJournal,
                    recoverySafe: hasJournal || ((try? store.load().restored) ?? true)
                )
                $0.defaultDatabase = database
                return database
            }
            let backups = BackupCoordinator(database: database, store: store)
            _backups = State(initialValue: backups)
            if !hasJournal { backups.registerBackgroundTask() }
            widgetTimelineInvalidator = WidgetTimelineInvalidator(database: database)
            calendarSyncCoordinator = CalendarSyncCoordinator(
                database: database, calendarClient: .live(), contactClient: .liveValue
            )
            startupError = nil
            AppDependencyManager.shared.add(
                dependency: ClinicalAppActions(router: router, database: database)
            )
        } catch {
            _backups = State(initialValue: nil)
            widgetTimelineInvalidator = nil
            calendarSyncCoordinator = nil
            startupError =
                "Clinical could not open its data. Keep the app installed and contact support for assisted recovery."
        }
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
