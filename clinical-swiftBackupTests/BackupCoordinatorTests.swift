import ClinicalPersistence
import Dependencies
import Foundation
import GRDB
import Testing

@testable import clinical_swift

// The network suite must serialize these tests because the URL protocol shares one handler.
extension BackupNetworkTests {
    @Test func coordinatorResumesPartialPairWithSavedIDs() async throws {
        let fixture = try await CoordinatorFixture.make()
        defer { fixture.cleanUp() }
        let remote = CoordinatorDrive(fixture)
        let testSession = session { try await remote.respond(to: $0) }
        defer { testSession.invalidateAndCancel() }
        let coordinator = fixture.coordinator(session: testSession)

        #expect(await fixture.run(coordinator))

        #expect(remote.uploads == ["manifest-id"])
        #expect(remote.databaseReads == 1)
        let saved = try fixture.store.load()
        #expect(saved.lastSuccess == fixture.snapshot.manifest)
        #expect(saved.pending == nil)
        #expect(saved.problem == nil)
        #expect(saved.retryAfter == nil)
        #expect(saved.failureCount == 0)
        #expect(!coordinator.isRunning)
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshot.directory.path()))
    }

    @Test func coordinatorCancellationRetainsPendingBytesAndIDsForRestart() async throws {
        let fixture = try await CoordinatorFixture.make()
        defer { fixture.cleanUp() }
        let remote = CoordinatorDrive(fixture)
        remote.holdDatabaseRead = true
        let testSession = session { try await remote.respond(to: $0) }
        defer { testSession.invalidateAndCancel() }
        let coordinator = fixture.coordinator(session: testSession)
        let work = Task { await fixture.run(coordinator) }
        defer {
            coordinator.cancel()
            work.cancel()
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while remote.databaseReads == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(remote.databaseReads == 1, "The saved database file was not requested.")

        coordinator.cancel()
        #expect(await work.value == false)

        try fixture.expectPendingCopy()
        #expect(remote.uploads.isEmpty)
        #expect(!coordinator.isRunning)
        remote.holdDatabaseRead = false
        #expect(await fixture.run(fixture.coordinator(session: testSession)))
        #expect(remote.uploads == ["manifest-id"])
        #expect(try fixture.store.load().lastSuccess == fixture.snapshot.manifest)
    }

    @Test func coordinatorKeepsRetryCopyUntilSuccessStateCanBeSaved() async throws {
        let fixture = try await CoordinatorFixture.make()
        defer { fixture.cleanUp() }
        let remote = CoordinatorDrive(fixture)
        let savedState = fixture.store.directory.appending(path: "saved-state.json")
        remote.beforeManifestConfirmation = {
            // A directory at state.json makes the atomic success write fail after remote confirmation.
            try FileManager.default.moveItem(at: fixture.store.stateURL, to: savedState)
            try FileManager.default.createDirectory(
                at: fixture.store.stateURL, withIntermediateDirectories: false)
        }
        let testSession = session { try await remote.respond(to: $0) }
        defer { testSession.invalidateAndCancel() }
        let coordinator = fixture.coordinator(session: testSession)

        #expect(await fixture.run(coordinator) == false)

        #expect(remote.uploads == ["manifest-id"])
        try FileManager.default.removeItem(at: fixture.store.stateURL)
        try FileManager.default.moveItem(at: savedState, to: fixture.store.stateURL)
        try fixture.expectPendingCopy()
        remote.beforeManifestConfirmation = nil
        #expect(await fixture.run(fixture.coordinator(session: testSession)))
        #expect(remote.uploads == ["manifest-id"])
        #expect(try fixture.store.load().lastSuccess == fixture.snapshot.manifest)
        #expect(try fixture.store.load().pending == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshot.directory.path()))
    }
}

@MainActor
private struct CoordinatorFixture {
    let database: DatabasePool
    let store: BackupStateStore
    let snapshot: BackupSnapshot
    let keychain: BackupKeychain
    let databaseBytes: Data
    let manifestBytes: Data

    static func make() async throws -> Self {
        let directory = try BackupFixture.directory()
        let database = try BackupFixture.database(at: directory.appending(path: "source.db"))
        let store = BackupStateStore(directory: directory.appending(path: "backups"))
        let snapshot = try await BackupSnapshotWorker().capture(
            database: database, directory: store.directory.appending(path: "pending"),
            datasetID: BackupFixture.datasetID, capturedAt: BackupFixture.capturedAt,
            appVersion: "test")
        var state = BackupState()
        state.datasetID = BackupFixture.datasetID
        state.accountID = "test-account"
        state.rootFolderID = "root"
        state.datasetFolderID = "folder"
        state.pending = BackupPendingUpload(
            manifest: snapshot.manifest, accountID: "test-account",
            databaseFileID: "database-id", manifestFileID: "manifest-id")
        try store.save(state)
        let keychain = BackupKeychain(
            service: "in.bitehaus.clinical.coordinator-" + UUID().uuidString)
        try keychain.save(
            GoogleBackupTokens(
                accountID: "test-account", email: "test@example.invalid", clientID: "test-client",
                accessToken: "test-token", refreshToken: "test-refresh", expiresAt: .distantFuture))
        return Self(
            database: database, store: store, snapshot: snapshot, keychain: keychain,
            databaseBytes: try Data(contentsOf: snapshot.databaseURL),
            manifestBytes: try Data(contentsOf: snapshot.manifestURL))
    }

    func coordinator(session: URLSession) -> BackupCoordinator {
        BackupCoordinator(
            database: database, store: store,
            account: GoogleBackupAccount(session: session, keychain: keychain), session: session)
    }

    func run(_ coordinator: BackupCoordinator) async -> Bool {
        await withDependencies {
            $0.date.now = BackupFixture.capturedAt
        } operation: {
            await coordinator.opportunity()
        }
    }

    func expectPendingCopy() throws {
        let state = try store.load()
        #expect(state.pending?.manifest == snapshot.manifest)
        #expect(state.pending?.accountID == "test-account")
        #expect(state.pending?.databaseFileID == "database-id")
        #expect(state.pending?.manifestFileID == "manifest-id")
        #expect(state.lastSuccess == nil)
        #expect(state.problem == nil)
        #expect(state.retryAfter == nil)
        #expect(state.failureCount == 0)
        #expect(try Data(contentsOf: snapshot.databaseURL) == databaseBytes)
        #expect(try Data(contentsOf: snapshot.manifestURL) == manifestBytes)
    }

    func cleanUp() {
        keychain.remove()
        try? database.close()
        try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent())
    }
}

@MainActor
private final class CoordinatorDrive {
    let fixture: CoordinatorFixture
    let databaseFile: DriveBackupFile
    let manifestFile: DriveBackupFile
    var manifestUploaded = false
    var holdDatabaseRead = false
    var beforeManifestConfirmation: (() throws -> Void)?
    var databaseReads = 0
    var uploads: [String] = []

    init(_ fixture: CoordinatorFixture) {
        self.fixture = fixture
        let manifest = fixture.snapshot.manifest
        func file(_ id: String, role: String, bytes: Data) -> DriveBackupFile {
            DriveBackupFile(
                id: id, size: String(bytes.count), sha256Checksum: BackupFiles.checksum(bytes),
                parents: ["folder"],
                appProperties: [
                    "clinical": "backup", "dataset": manifest.datasetID.uuidString,
                    "snapshot": manifest.snapshotID.uuidString, "role": role,
                    "capturedAt": manifest.capturedAt.formatted(.iso8601),
                    "sha256": BackupFiles.checksum(bytes),
                ])
        }
        databaseFile = file("database-id", role: "database", bytes: fixture.databaseBytes)
        manifestFile = file("manifest-id", role: "manifest", bytes: fixture.manifestBytes)
    }

    func respond(to request: URLRequest) async throws -> (Int, Data) {
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        switch (request.httpMethod, request.url?.path) {
        case ("GET", "/drive/v3/files/root"):
            return (
                200, Data(#"{"id":"root","mimeType":"application/vnd.google-apps.folder"}"#.utf8)
            )
        case ("GET", "/drive/v3/files/folder"):
            return (
                200,
                Data(
                    #"{"id":"folder","mimeType":"application/vnd.google-apps.folder","parents":["root"]}"#
                        .utf8)
            )
        case ("GET", "/drive/v3/files/database-id"):
            databaseReads += 1
            if holdDatabaseRead { try await Task.sleep(for: .seconds(5)) }
            return (200, try JSONEncoder().encode(databaseFile))
        case ("GET", "/drive/v3/files/manifest-id"):
            guard manifestUploaded else { return (404, Data()) }
            try beforeManifestConfirmation?()
            return (200, try JSONEncoder().encode(manifestFile))
        case ("POST", "/upload/drive/v3/files"):
            let body = try requestBody(request)
            #expect(body.range(of: fixture.manifestBytes) != nil)
            #expect(body.range(of: Data(#""id":"manifest-id""#.utf8)) != nil)
            try fixture.expectPendingCopy()
            uploads.append("manifest-id")
            manifestUploaded = true
            return (200, try JSONEncoder().encode(manifestFile))
        case ("GET", "/drive/v3/files"):
            let files = [databaseFile, manifestFile]
            return (
                200,
                try JSONSerialization.data(withJSONObject: [
                    "files": JSONSerialization.jsonObject(with: JSONEncoder().encode(files))
                ])
            )
        default:
            Issue.record(
                "Unexpected Drive request: \(request.httpMethod ?? "") \(request.url?.path ?? "")")
            throw BackupError.drive(400)
        }
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            try #require(count >= 0, "The upload body could not be read.")
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
