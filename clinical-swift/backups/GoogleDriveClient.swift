import Foundation

nonisolated struct DriveBackupFile: Codable, Equatable, Sendable {
    let id: String
    var name: String?
    var mimeType: String?
    var size: String?
    var sha256Checksum: String?
    var parents: [String]?
    var trashed: Bool?
    var shared: Bool?
    var appProperties: [String: String]?
}

nonisolated struct DriveBackupPair: Sendable {
    let database: DriveBackupFile
    let manifest: DriveBackupFile
    let capturedAt: Date
}

nonisolated struct GoogleDriveClient: Sendable {
    var session: URLSession = .shared
    let token: @Sendable () async throws -> String
    private static let fields =
        "id,name,mimeType,size,sha256Checksum,parents,trashed,shared,appProperties"

    static func check(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw BackupError.drive(0) }
        guard (200..<300).contains(response.statusCode) else {
            throw BackupError.drive(response.statusCode)
        }
    }

    func generateIDs(count: Int = 2) async throws -> [String] {
        struct Response: Decodable { let ids: [String] }
        let data = try await request(
            "files/generateIds", query: ["count": String(count), "space": "drive"])
        let ids = try JSONDecoder().decode(Response.self, from: data).ids
        guard ids.count == count else { throw BackupError.drive(0) }
        return ids
    }

    func file(_ id: String) async throws -> DriveBackupFile? {
        do {
            let data = try await request("files/" + id, query: ["fields": Self.fields])
            return try JSONDecoder().decode(DriveBackupFile.self, from: data)
        } catch BackupError.drive(404) { return nil }
    }

    func requireFolder(_ id: String, parent: String? = nil) async throws {
        guard let file = try await file(id), file.mimeType == "application/vnd.google-apps.folder",
            file.trashed != true, file.shared != true,
            parent.map({ file.parents?.contains($0) == true }) != false
        else { throw BackupError.missingFolder }
    }

    func createFolder(name: String, parent: String? = nil, datasetID: UUID? = nil) async throws
        -> String
    {
        let ids = try await generateIDs(count: 1)
        guard let id = ids.first else { throw BackupError.drive(0) }
        let metadata = DriveBackupFile(
            id: id, name: name, mimeType: "application/vnd.google-apps.folder",
            parents: parent.map { [$0] },
            appProperties: ["clinical": "backup", "dataset": datasetID?.uuidString ?? "root"]
        )
        _ = try await request(
            "files", method: "POST", query: ["fields": "id"], body: JSONEncoder().encode(metadata))
        return id
    }

    func upload(
        _ url: URL, id: String, parent: String, name: String,
        manifest: BackupManifest, role: String
    ) async throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let properties = [
            "clinical": "backup", "dataset": manifest.datasetID.uuidString,
            "snapshot": manifest.snapshotID.uuidString, "role": role,
            "capturedAt": manifest.capturedAt.formatted(.iso8601),
            "sha256": BackupFiles.checksum(data),
        ]
        if let existing = try await file(id) {
            try confirm(existing, parent: parent, data: data, properties: properties)
            return
        }
        let metadata = DriveBackupFile(
            id: id, name: name,
            mimeType: role == "database" ? "application/vnd.sqlite3" : "application/json",
            parents: [parent], appProperties: properties
        )
        let boundary = "clinical-" + UUID().uuidString
        var body = Data(
            "--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body.append(try JSONEncoder().encode(metadata))
        body.append(
            Data("\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        do {
            _ = try await request(
                "files", method: "POST", query: ["uploadType": "multipart", "fields": Self.fields],
                body: body, contentType: "multipart/related; boundary=" + boundary, upload: true
            )
        } catch BackupError.drive(409) {
            // A conflict can be a lost success response. The stored bytes must still match.
        }
        guard let uploaded = try await file(id) else { throw BackupError.drive(0) }
        try confirm(uploaded, parent: parent, data: data, properties: properties)
    }

    private func confirm(
        _ file: DriveBackupFile, parent: String, data: Data, properties: [String: String]
    ) throws {
        guard file.trashed != true, file.shared != true, file.parents == [parent],
            file.size == String(data.count), file.sha256Checksum == BackupFiles.checksum(data),
            file.appProperties == properties
        else { throw BackupError.invalidSnapshot }
    }

    func list(parent: String) async throws -> [DriveBackupFile] {
        struct Page: Decodable {
            let files: [DriveBackupFile]
            let nextPageToken: String?
        }
        var files: [DriveBackupFile] = []
        var pageToken: String?
        repeat {
            var query = [
                "q": "'\(parent)' in parents and trashed = false",
                "fields": "nextPageToken,files(\(Self.fields))", "pageSize": "1000",
            ]
            query["pageToken"] = pageToken
            let page = try JSONDecoder().decode(
                Page.self, from: await request("files", query: query))
            files.append(contentsOf: page.files)
            pageToken = page.nextPageToken
        } while pageToken != nil
        return files
    }

    static func completePairs(_ files: [DriveBackupFile], datasetID: UUID) -> [DriveBackupPair] {
        let owned = files.filter {
            $0.appProperties?["clinical"] == "backup"
                && $0.appProperties?["dataset"] == datasetID.uuidString
                && $0.trashed != true && $0.shared != true
        }
        let groups = Dictionary(grouping: owned, by: { $0.appProperties?["snapshot"] ?? "" })
        return groups.compactMap { snapshotID, group in
            guard UUID(uuidString: snapshotID) != nil, group.count == 2,
                let database = group.first(where: { $0.appProperties?["role"] == "database" }),
                let manifest = group.first(where: { $0.appProperties?["role"] == "manifest" }),
                let captured = database.appProperties?["capturedAt"],
                captured == manifest.appProperties?["capturedAt"],
                let date = try? Date(captured, strategy: .iso8601)
            else { return nil }
            return DriveBackupPair(database: database, manifest: manifest, capturedAt: date)
        }.sorted { $0.capturedAt > $1.capturedAt }
    }

    func download(_ id: String, to url: URL) async throws {
        let data = try await request("files/" + id, query: ["alt": "media"])
        try data.write(to: url, options: .atomic)
        try BackupFiles.protect(url)
    }

    func delete(_ id: String) async throws {
        do { _ = try await request("files/" + id, method: "DELETE") } catch BackupError.drive(404) {
            return
        }
    }

    private func request(
        _ path: String, method: String = "GET", query: [String: String] = [:],
        body: Data? = nil, contentType: String = "application/json", upload: Bool = false
    ) async throws -> Data {
        let base =
            upload
            ? "https://www.googleapis.com/upload/drive/v3/" : "https://www.googleapis.com/drive/v3/"
        guard var components = URLComponents(string: base + path) else {
            throw BackupError.drive(0)
        }
        components.queryItems = query.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        guard let url = components.url else { throw BackupError.drive(0) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        return data
    }
}
