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
        do {
            var store = BackupStateStore.live()
            var backupKeychain = BackupKeychain()
            var authorizeCheck = false
            #if INTERNAL_BACKUP_CHECK
                authorizeCheck = CommandLine.arguments.contains("--backup-check-authorize")
                if authorizeCheck {
                    store = BackupStateStore(
                        directory: URL.applicationSupportDirectory.appending(
                            path: "ClinicalBackupCheck"))
                    backupKeychain = BackupKeychain(service: "in.bitehaus.clinical.backups.check")
                }
            #endif
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
                let database: any DatabaseWriter
                if authorizeCheck {
                    let isolated = try DatabaseQueue()
                    try databaseMigrator(allowDebugErasure: false).migrate(isolated)
                    database = isolated
                } else {
                    database = try appDatabase(
                        seedSamples: !hasJournal,
                        recoverySafe: hasJournal || ((try? store.load().restored) ?? true)
                    )
                }
                $0.defaultDatabase = database
                return database
            }
            let backups = BackupCoordinator(
                database: database, store: store,
                account: GoogleBackupAccount(keychain: backupKeychain))
            if authorizeCheck { router.requestSettings() }
            _backups = State(initialValue: backups)
            if !hasJournal, !authorizeCheck { backups.registerBackgroundTask() }
            widgetTimelineInvalidator = WidgetTimelineInvalidator(database: database)
            calendarSyncCoordinator =
                authorizeCheck
                ? nil
                : CalendarSyncCoordinator(
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
                            if CommandLine.arguments.contains("--ui-testing-appointment-hitboxes") {
                                AppointmentHitboxUITestView()
                            } else {
                                ContentView(router: router)
                            }
                        #else
                            ContentView(router: router)
                        #endif
                    }
                    .environment(backups)
                }
            }
            .task {
                await backups?.opportunity()
            }
            .task {
                await calendarSyncCoordinator?.activate()
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
