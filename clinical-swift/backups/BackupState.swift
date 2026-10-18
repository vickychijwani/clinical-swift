import Foundation

nonisolated struct BackupPendingUpload: Codable, Sendable {
    let manifest: BackupManifest
    let accountID: String
    var databaseFileID: String?
    var manifestFileID: String?

    func snapshot(in store: BackupStateStore) -> BackupSnapshot {
        BackupSnapshot(
            manifest: manifest,
            directory: store.directory.appending(path: "pending").appending(
                path: manifest.snapshotID.uuidString))
    }
}

nonisolated extension BackupPendingUpload {
    private enum CodingKeys: String, CodingKey {
        case manifest, accountID, databaseFileID, manifestFileID
    }

    private enum LegacyCodingKeys: String, CodingKey { case snapshot }
    private struct LegacySnapshot: Decodable { let manifest: BackupManifest }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let manifest = try values.decodeIfPresent(BackupManifest.self, forKey: .manifest) {
            self.manifest = manifest
        } else {
            // Old state includes a container URL. Only its manifest is needed to find owned files.
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            manifest = try legacy.decode(LegacySnapshot.self, forKey: .snapshot).manifest
        }
        accountID = try values.decode(String.self, forKey: .accountID)
        databaseFileID = try values.decodeIfPresent(String.self, forKey: .databaseFileID)
        manifestFileID = try values.decodeIfPresent(String.self, forKey: .manifestFileID)
    }
}

nonisolated struct BackupState: Codable, Sendable {
    var datasetID = UUID()
    var accountID: String?
    var accountEmail: String?
    var rootFolderID: String?
    var datasetFolderID: String?
    var pending: BackupPendingUpload?
    var lastSuccess: BackupManifest?
    var problem: String?
    var retryAfter: Date?
    var failureCount = 0
    var restored = false
    var pendingDeletions: [String] = []

    func isDue(at date: Date) -> Bool {
        pending != nil
            || lastSuccess.map { date.timeIntervalSince($0.capturedAt) >= 86_400 } != false
    }

    func needsAttention(at date: Date) -> Bool {
        accountID == nil || problem != nil
            || lastSuccess.map { date.timeIntervalSince($0.capturedAt) >= 172_800 } == true
            || pending.map { date.timeIntervalSince($0.manifest.capturedAt) >= 172_800 }
                == true
    }
}

/// This file remains available when the clinical database cannot open.
nonisolated struct BackupStateStore: Sendable {
    let directory: URL

    static func live() -> Self {
        Self(directory: URL.applicationSupportDirectory.appending(path: "ClinicalBackups"))
    }

    var stateURL: URL { directory.appending(path: "state.json") }

    func load() throws -> BackupState {
        guard FileManager.default.fileExists(atPath: stateURL.path(percentEncoded: false)) else {
            return BackupState()
        }
        return try BackupFiles.load(BackupState.self, from: stateURL)
    }

    func save(_ state: BackupState) throws {
        try BackupFiles.createDirectory(directory)
        try BackupFiles.save(state, to: stateURL)
    }
}

nonisolated enum BackupRetention {
    static func fileIDsToDelete(_ pairs: [DriveBackupPair], at date: Date, lastSuccess: UUID?)
        -> [String]
    {
        // Protect both the newest remote pair and this installation's confirmed success.
        pairs.sorted { $0.capturedAt > $1.capturedAt }.dropFirst().filter {
            date.timeIntervalSince($0.capturedAt) > 30 * 86_400
                && (lastSuccess == nil
                    || $0.database.appProperties?["snapshot"] != lastSuccess?.uuidString)
        }.flatMap { [$0.manifest.id, $0.database.id] }
    }
}
