import ClinicalPersistence
import Foundation
import GRDB
import Testing

@testable import clinical_swift

@MainActor
struct BackupDriveTests {
    @Test func realDriveRoundTripUsesDownloadedBytes() async throws {
        let path = ProcessInfo.processInfo.environment["CLINICAL_BACKUP_CHECK_CREDENTIALS"] ?? ""
        try #require(
            !path.isEmpty && !path.contains("$("),
            "The Drive credential path was not passed to the test runner.")
        var tokens = try BackupFiles.load(GoogleBackupTokens.self, from: URL(filePath: path))
        // Every release check exercises the refresh path, even with a fresh access token.
        tokens.expiresAt = .distantPast
        let keychain = BackupKeychain(
            service: "in.bitehaus.clinical.backups.test-" + UUID().uuidString)
        try keychain.save(tokens)
        defer { keychain.remove() }
        let account = GoogleBackupAccount(keychain: keychain)
        let accountID = tokens.accountID
        let drive = GoogleDriveClient(token: {
            try await account.accessToken(expectedAccountID: accountID)
        })
        let directory = try BackupFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try BackupFixture.database(at: directory.appending(path: "source.db"))
        let expected = try BackupFixture.contents(source)
        let snapshot = try await BackupSnapshotWorker().capture(
            database: source, directory: directory.appending(path: "upload"), datasetID: UUID(),
            capturedAt: BackupFixture.capturedAt, appVersion: "drive-check")
        try source.close()
        let folder = try await drive.createFolder(
            name: "Clinical Backup Check " + snapshot.manifest.datasetID.uuidString,
            datasetID: snapshot.manifest.datasetID)
        do {
            let ids = try await drive.generateIDs()
            try await drive.upload(
                snapshot.databaseURL, id: ids[0], parent: folder, name: "synthetic.db",
                manifest: snapshot.manifest, role: "database")
            // Repeat the same ID to verify reconciliation after an unknown upload result.
            try await drive.upload(
                snapshot.databaseURL, id: ids[0], parent: folder, name: "synthetic.db",
                manifest: snapshot.manifest, role: "database")
            try await drive.upload(
                snapshot.manifestURL, id: ids[1], parent: folder, name: "synthetic.json",
                manifest: snapshot.manifest, role: "manifest")
            let pairs = GoogleDriveClient.completePairs(
                try await drive.list(parent: folder), datasetID: snapshot.manifest.datasetID)
            #expect(pairs.count == 1)
            let download = directory.appending(path: "download")
            try BackupFiles.createDirectory(download)
            try await drive.download(ids[0], to: download.appending(path: "snapshot.db"))
            try await drive.download(ids[1], to: download.appending(path: "snapshot.json"))
            // Remove local upload bytes before reading the downloaded pair.
            try FileManager.default.removeItem(at: snapshot.directory)
            let manifest = try BackupFiles.load(
                BackupManifest.self, from: download.appending(path: "snapshot.json"))
            #expect(manifest == snapshot.manifest)
            let retrieved = BackupSnapshot(manifest: manifest, directory: download)
            try BackupFiles.validate(retrieved, supportedMigrations: databaseMigrator().migrations)
            var configuration = Configuration()
            configuration.readonly = true
            let database = try DatabaseQueue(
                path: retrieved.databaseURL.path(percentEncoded: false), configuration: configuration)
            #expect(try BackupFixture.contents(database) == expected)
            try database.close()
            try await drive.delete(folder)
        } catch {
            try? await drive.delete(folder)
            throw error
        }
    }
}
