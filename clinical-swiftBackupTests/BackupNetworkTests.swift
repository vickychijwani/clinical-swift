import Foundation
import Synchronization
import Testing

@testable import clinical_swift

nonisolated final class BackupURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (Int, Data)
    static let handler = Mutex<Handler?>(nil)
    private let work = Mutex<Task<Void, Never>?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        work.withLock { work in
            work = Task {
                do {
                    let handle = Self.handler.withLock { $0 }
                    guard let handle, let url = request.url else { throw BackupError.drive(0) }
                    let (status, data) = try await handle(request)
                    guard
                        let response = HTTPURLResponse(
                            url: url, statusCode: status, httpVersion: nil, headerFields: nil)
                    else { throw BackupError.drive(0) }
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: data)
                    client?.urlProtocolDidFinishLoading(self)
                } catch {
                    if !Task.isCancelled { client?.urlProtocol(self, didFailWithError: error) }
                }
            }
        }
    }
    override func stopLoading() { work.withLock { $0?.cancel() } }
}

@Suite(.serialized)
@MainActor
struct BackupNetworkTests {
    func session(_ handler: @escaping BackupURLProtocol.Handler) -> URLSession {
        BackupURLProtocol.handler.withLock { $0 = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BackupURLProtocol.self]
        configuration.timeoutIntervalForResource = 5
        return URLSession(configuration: configuration)
    }

    @Test func uploadAcceptsOnlyMatchingStoredBytes() async throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "data")
        let bytes = Data("synthetic".utf8)
        try bytes.write(to: url)
        let manifest = BackupManifest(
            formatVersion: 1, datasetID: BackupFixture.datasetID, snapshotID: UUID(),
            capturedAt: BackupFixture.capturedAt, appVersion: "test", migrations: [],
            byteCount: bytes.count, sha256: BackupFiles.checksum(bytes))
        let properties = [
            "clinical": "backup", "dataset": manifest.datasetID.uuidString,
            "snapshot": manifest.snapshotID.uuidString, "role": "database",
            "capturedAt": manifest.capturedAt.formatted(.iso8601), "sha256": manifest.sha256,
        ]
        let file = DriveBackupFile(
            id: "saved-id", size: String(bytes.count), sha256Checksum: manifest.sha256,
            parents: ["folder"], appProperties: properties)
        let matching = try JSONEncoder().encode(file)
        let calls = Mutex(0)
        let drive = GoogleDriveClient(
            session: session { request in
                calls.withLock { $0 += 1 }
                return (200, matching)
            }, token: { "test" })
        try await drive.upload(
            url, id: "saved-id", parent: "folder", name: "data.db", manifest: manifest,
            role: "database")
        #expect(calls.withLock { $0 } == 1)
        var wrong = file
        wrong.sha256Checksum = "wrong"
        let mismatched = try JSONEncoder().encode(wrong)
        let bad = GoogleDriveClient(session: session { _ in (200, mismatched) }, token: { "test" })
        await #expect(throws: BackupError.invalidSnapshot) {
            try await bad.upload(
                url, id: "saved-id", parent: "folder", name: "data.db", manifest: manifest,
                role: "database")
        }
    }

    @Test func conflictWithoutConfirmedFileIsNotSuccess() async throws {
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "data")
        try Data("synthetic".utf8).write(to: url)
        let manifest = BackupManifest(
            formatVersion: 1, datasetID: BackupFixture.datasetID, snapshotID: UUID(),
            capturedAt: BackupFixture.capturedAt, appVersion: "test", migrations: [], byteCount: 9,
            sha256: "test")
        let drive = GoogleDriveClient(
            session: session { request in
                (request.httpMethod == "POST" ? 409 : 404, Data())
            }, token: { "test" })
        await #expect(throws: BackupError.drive(0)) {
            try await drive.upload(
                url, id: "same-id", parent: "folder", name: "data.db", manifest: manifest,
                role: "database")
        }
    }

    @Test func refreshAndAccountBindingUseSeparateCredentials() async throws {
        let keychain = BackupKeychain(
            service: "in.bitehaus.clinical.backups.unit-" + UUID().uuidString)
        defer { keychain.remove() }
        try keychain.save(
            GoogleBackupTokens(
                accountID: "original", email: "test@example.invalid", clientID: "client",
                accessToken: "expired", refreshToken: "refresh", expiresAt: .distantPast))
        let account = GoogleBackupAccount(
            session: session { request in
                guard request.url?.path == "/token", request.httpMethod == "POST" else {
                    throw BackupError.drive(0)
                }
                return (200, Data(#"{"access_token":"refreshed","expires_in":3600}"#.utf8))
            }, keychain: keychain)
        await #expect(throws: BackupError.accountChanged) {
            try await account.accessToken(expectedAccountID: "another")
        }
        #expect(try await account.accessToken(expectedAccountID: "original") == "refreshed")
        #expect(try keychain.load().accessToken == "refreshed")
        #expect(try keychain.load().refreshToken == "refresh")
    }

    @Test func cancellingBackupStopsRefreshAndRetainsCredentials() async throws {
        let keychain = BackupKeychain(
            service: "in.bitehaus.clinical.backups.unit-" + UUID().uuidString)
        defer { keychain.remove() }
        try keychain.save(
            GoogleBackupTokens(
                accountID: "original", email: "test@example.invalid", clientID: "client",
                accessToken: "expired", refreshToken: "refresh", expiresAt: .distantPast))
        let (started, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        let cancelled = Mutex(false)
        let testSession = session { _ in
            try await withTaskCancellationHandler {
                continuation.yield(())
                try await Task.sleep(for: .seconds(30))
                return (200, Data(#"{"access_token":"unexpected","expires_in":3600}"#.utf8))
            } onCancel: {
                cancelled.withLock { $0 = true }
            }
        }
        defer { testSession.invalidateAndCancel() }
        let account = GoogleBackupAccount(session: testSession, keychain: keychain)
        let backup = Task { try await account.accessToken(expectedAccountID: "original") }
        defer { backup.cancel() }
        var events = started.makeAsyncIterator()
        try #require(await events.next() != nil)
        backup.cancel()
        do {
            _ = try await backup.value
            Issue.record("A cancelled refresh must fail.")
        } catch {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        #expect(cancelled.withLock { $0 })
        #expect(try keychain.load().accessToken == "expired")
        #expect(try keychain.load().refreshToken == "refresh")
        BackupURLProtocol.handler.withLock { handler in
            handler = { _ in
                (200, Data(#"{"access_token":"refreshed","expires_in":3600}"#.utf8))
            }
        }
        #expect(try await account.accessToken(expectedAccountID: "original") == "refreshed")
    }

    @Test func paginationAndCompletePairsExcludeForeignAndPartialFiles() async throws {
        let dataset = BackupFixture.datasetID
        let snapshot = UUID().uuidString
        let props = [
            "clinical": "backup", "dataset": dataset.uuidString, "snapshot": snapshot,
            "capturedAt": BackupFixture.capturedAt.formatted(.iso8601),
        ]
        var database = DriveBackupFile(
            id: "db", size: "10", sha256Checksum: "hash",
            appProperties: props.merging(["role": "database"]) { _, new in new })
        let manifest = DriveBackupFile(
            id: "json", size: "20", sha256Checksum: "hash",
            appProperties: props.merging(["role": "manifest"]) { _, new in new })
        let first = try JSONSerialization.data(withJSONObject: [
            "files": [try JSONSerialization.jsonObject(with: JSONEncoder().encode(database))],
            "nextPageToken": "page2",
        ])
        let second = try JSONSerialization.data(withJSONObject: [
            "files": [try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest))]
        ])
        let drive = GoogleDriveClient(
            session: session { request in
                (200, request.url?.query?.contains("pageToken=page2") == true ? second : first)
            }, token: { "test" })
        let files = try await drive.list(parent: "folder")
        #expect(files.count == 2)
        #expect(GoogleDriveClient.completePairs(files, datasetID: dataset).count == 1)
        #expect(GoogleDriveClient.completePairs([database], datasetID: dataset).isEmpty)
        #expect(GoogleDriveClient.completePairs(files, datasetID: UUID()).isEmpty)
        database.shared = true
        #expect(GoogleDriveClient.completePairs([database, manifest], datasetID: dataset).isEmpty)
    }
}
