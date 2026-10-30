import BackgroundTasks
import ClinicalPersistence
import Dependencies
import Foundation
import GRDB
import Observation

@MainActor @Observable
final class BackupCoordinator {
    @ObservationIgnored @Dependency(\.date.now) private var now
    private(set) var state: BackupState
    private(set) var isRunning = false
    private(set) var isConnecting = false
    var isForeground = true
    private let database: any DatabaseWriter
    private let store: BackupStateStore
    private let account: GoogleBackupAccount
    private let session: URLSession
    private let snapshotWorker = BackupSnapshotWorker()
    private var work: Task<Bool, Never>?
    private var stateIsReadable = true
    nonisolated static let backgroundIdentifier = "in.bitehaus.clinical.backup"

    init(
        database: any DatabaseWriter, store: BackupStateStore = .live(),
        account: GoogleBackupAccount = GoogleBackupAccount(), session: URLSession = .shared
    ) {
        self.database = database
        self.store = store
        self.account = account
        self.session = session
        do { state = try store.load() } catch {
            state = BackupState()
            state.problem =
                "Backup state could not be read. Keep the saved files and contact support."
            stateIsReadable = false
        }
    }

    var needsAttention: Bool { state.needsAttention(at: now) || !stateIsReadable }

    var status: String {
        if isRunning { return "Backup running" }
        if needsAttention { return "Backup needs attention" }
        if state.lastSuccess != nil { return "Backup successful" }
        return "Waiting for backup"
    }

    var problem: String? {
        if let problem = state.problem { return problem }
        if state.accountID == nil { return BackupError.authorizationRequired.localizedDescription }
        if needsAttention { return "A confirmed backup is overdue. Keep Clinical open to retry." }
        return nil
    }

    func connect(
        authenticate: (GoogleAuthorizationRequest) async throws -> URL
    ) async {
        guard !isConnecting, !isRunning, stateIsReadable else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let request = try GoogleAuthorizationRequest(configuration: .live())
            let callback = try await authenticate(request)
            // Account binding also protects a confirmed dataset, even with no pending upload.
            let tokens = try await account.complete(
                request, callback: callback, expectedAccountID: state.accountID)
            state.accountID = tokens.accountID
            state.accountEmail = tokens.email
            state.retryAfter = nil
            try store.save(state)
            await opportunity()
        } catch {
            state.problem = error.localizedDescription
            try? store.save(state)
        }
    }

    @discardableResult
    func opportunity() async -> Bool {
        if let work { return await work.value }
        let task = Task { await self.perform() }
        work = task
        let success = await task.value
        work = nil
        scheduleBackground()
        return success
    }

    func cancel() { work?.cancel() }

    func retry() async {
        guard !isRunning else { return }
        state.retryAfter = nil
        await opportunity()
    }

    private func perform() async -> Bool {
        guard
            !FileManager.default.fileExists(
                atPath: store.directory.appending(path: "restore.json").path(percentEncoded: false))
        else {
            state.problem =
                "Verify restored data and finalize recovery before starting a new backup."
            return false
        }
        guard stateIsReadable, !isRunning, let accountID = state.accountID else { return false }
        guard state.retryAfter.map({ $0 <= now }) != false else { return false }
        isRunning = true
        defer { isRunning = false }
        let account = account
        let drive = GoogleDriveClient(
            session: session,
            token: {
                try await account.accessToken(expectedAccountID: accountID)
            })
        do {
            try Task.checkCancellation()
            if let root = state.rootFolderID {
                try await drive.requireFolder(root)
            } else {
                state.rootFolderID = try await drive.createFolder(name: "Clinical Backups")
                try store.save(state)
            }
            guard let root = state.rootFolderID else { throw BackupError.missingFolder }
            if let folder = state.datasetFolderID {
                try await drive.requireFolder(folder, parent: root)
            } else {
                state.datasetFolderID = try await drive.createFolder(
                    name: state.datasetID.uuidString, parent: root, datasetID: state.datasetID
                )
                try store.save(state)
            }
            guard let folder = state.datasetFolderID else { throw BackupError.missingFolder }
            if state.isDue(at: now) {
                if state.pending == nil {
                    let snapshot = try await snapshotWorker.capture(
                        database: database, directory: store.directory.appending(path: "pending"),
                        datasetID: state.datasetID, capturedAt: now,
                        appVersion: Bundle.main.object(
                            forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                            ?? "unknown"
                    )
                    state.pending = BackupPendingUpload(
                        manifest: snapshot.manifest, accountID: accountID)
                    try store.save(state)
                }
                guard var pending = state.pending else { throw BackupError.invalidSnapshot }
                guard pending.accountID == accountID else { throw BackupError.accountChanged }
                let snapshot = pending.snapshot(in: store)
                try await snapshotWorker.validate(
                    snapshot, supportedMigrations: databaseMigrator().migrations)
                if pending.databaseFileID == nil || pending.manifestFileID == nil {
                    let ids = try await drive.generateIDs()
                    pending.databaseFileID = ids[0]
                    pending.manifestFileID = ids[1]
                    state.pending = pending
                    try store.save(state)
                }
                guard let databaseID = pending.databaseFileID,
                    let manifestID = pending.manifestFileID
                else {
                    throw BackupError.invalidSnapshot
                }
                let manifest = pending.manifest
                let name =
                    manifest.capturedAt.formatted(.iso8601).replacing(":", with: "-") + "-"
                    + manifest.snapshotID.uuidString
                try await drive.upload(
                    snapshot.databaseURL, id: databaseID, parent: folder,
                    name: name + ".db", manifest: manifest, role: "database")
                try Task.checkCancellation()
                try await drive.upload(
                    snapshot.manifestURL, id: manifestID, parent: folder,
                    name: name + ".json", manifest: manifest, role: "manifest")
                // Persist success before releasing the only local retry copy.
                state.lastSuccess = manifest
                state.pending = nil
                state.problem = nil
                state.retryAfter = nil
                state.failureCount = 0
                try store.save(state)
                try? FileManager.default.removeItem(at: snapshot.directory)
            }
            try await prune(drive: drive, folder: folder)
            state.problem = nil
            state.failureCount = 0
            state.retryAfter = nil
            try store.save(state)
            return true
        } catch is CancellationError {
            return false
        } catch {
            if Task.isCancelled { return false }
            state.problem = error.localizedDescription
            state.failureCount = min(state.failureCount + 1, 10)
            state.retryAfter = now.addingTimeInterval(
                min(3600, 30 * pow(2, Double(state.failureCount))))
            try? store.save(state)
            return false
        }
    }

    private func prune(drive: GoogleDriveClient, folder: String) async throws {
        guard state.lastSuccess != nil else { return }
        let pairs = GoogleDriveClient.completePairs(
            try await drive.list(parent: folder), datasetID: state.datasetID)
        for id in BackupRetention.fileIDsToDelete(
            pairs, at: now, lastSuccess: state.lastSuccess?.snapshotID)
        where !state.pendingDeletions.contains(id) {
            state.pendingDeletions.append(id)
        }
        try store.save(state)
        while let id = state.pendingDeletions.first {
            try Task.checkCancellation()
            if let file = try await drive.file(id) {
                guard file.parents == [folder], file.shared != true,
                    file.appProperties?["clinical"] == "backup",
                    file.appProperties?["dataset"] == state.datasetID.uuidString,
                    file.appProperties?["snapshot"] != state.lastSuccess?.snapshotID.uuidString,
                    !pairs.prefix(1).contains(where: {
                        $0.database.id == id || $0.manifest.id == id
                    })
                else { throw BackupError.invalidSnapshot }
                try await drive.delete(id)
            }
            state.pendingDeletions.removeFirst()
            try store.save(state)
        }
    }

    func registerBackgroundTask() {
        // The launch handler inherits MainActor isolation, so iOS must call it on the main queue.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundIdentifier, using: .main
        ) { [weak self] task in
            Task { @MainActor in
                guard let self else {
                    task.setTaskCompleted(success: false)
                    return
                }
                task.expirationHandler = { @Sendable [weak self] in
                    Task { @MainActor in self?.cancel() }
                }
                NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
                let success = await self.opportunity()
                task.setTaskCompleted(success: success)
                if !self.isForeground {
                    NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
                }
            }
        }
    }

    func scheduleBackground() {
        guard state.accountID != nil else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundIdentifier)
        let request = BGProcessingTaskRequest(identifier: Self.backgroundIdentifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate =
            state.retryAfter ?? state.lastSuccess?.capturedAt.addingTimeInterval(86_400)
        do { try BGTaskScheduler.shared.submit(request) } catch {
            // Foreground opportunities still run when iOS cannot schedule background work.
        }
    }
}
