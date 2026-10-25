import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private struct AppStoreConnectError: Error, CustomStringConvertible {
    let description: String
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacing("+", with: "-")
        .replacing("/", with: "_")
        .replacing("=", with: "")
}

// OpenSSL emits DER integers. ES256 JWTs need two unsigned, 32-byte integers.
private func jwtSignature(from der: Data) throws -> Data {
    let bytes = Array(der)
    func invalid() -> AppStoreConnectError {
        AppStoreConnectError(description: "OpenSSL returned an invalid P-256 signature.")
    }
    guard bytes.count >= 8, bytes.count <= 72,
        bytes[0] == 0x30, Int(bytes[1]) == bytes.count - 2
    else { throw invalid() }
    var offset = 2
    var raw = Data()
    for _ in 0..<2 {
        guard offset + 2 <= bytes.count, bytes[offset] == 0x02 else { throw invalid() }
        let length = Int(bytes[offset + 1])
        offset += 2
        guard length > 0, length <= 33, offset + length <= bytes.count else { throw invalid() }
        var integer = Array(bytes[offset..<(offset + length)])
        offset += length
        guard integer[0] < 0x80 else { throw invalid() }
        if integer.count > 1 && integer[0] == 0 {
            guard integer[1] >= 0x80 else { throw invalid() }
            integer.removeFirst()
        }
        guard integer.count <= 32 else { throw invalid() }
        raw.append(contentsOf: repeatElement(UInt8(0), count: 32 - integer.count))
        raw.append(contentsOf: integer)
    }
    guard offset == bytes.count else { throw invalid() }
    return raw
}

private func sign(_ input: String, keyURL: URL) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["openssl", "dgst", "-sha256", "-sign", keyURL.path]
    let source = Pipe()
    let output = Pipe()
    process.standardInput = source
    process.standardOutput = output
    try process.run()
    try source.fileHandleForWriting.write(contentsOf: Data(input.utf8))
    try source.fileHandleForWriting.close()
    let signature = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw AppStoreConnectError(
            description:
                "OpenSSL signing failed. Check that openssl is on PATH and the API key is valid.")
    }
    return try jwtSignature(from: signature)
}

private func makeToken(keyID: String, issuerID: String, keyURL: URL) throws -> String {
    let now = Int(Date().timeIntervalSince1970)
    let header = try JSONSerialization.data(withJSONObject: [
        "alg": "ES256",
        "kid": keyID,
        "typ": "JWT",
    ])
    let payload = try JSONSerialization.data(withJSONObject: [
        "iss": issuerID,
        "iat": now,
        "exp": now + 10 * 60,
        "aud": "appstoreconnect-v1",
    ])
    let signingInput = "\(base64URL(header)).\(base64URL(payload))"
    let signature = try sign(signingInput, keyURL: keyURL)
    return "\(signingInput).\(base64URL(signature))"
}

private func requestJSON(from url: URL, token: String) async throws -> [String: Any] {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw AppStoreConnectError(description: "App Store Connect returned an invalid response.")
    }
    guard 200..<300 ~= httpResponse.statusCode else {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errors = json?["errors"] as? [[String: Any]]
        let detail = errors?.compactMap { $0["detail"] as? String }.joined(separator: " ")
        throw AppStoreConnectError(
            description:
                "App Store Connect returned HTTP \(httpResponse.statusCode). \(detail ?? "")"
                .trimmingCharacters(in: .whitespaces)
        )
    }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AppStoreConnectError(description: "App Store Connect returned invalid JSON.")
    }
    return json
}

private func appID(bundleID: String, token: String) async throws -> String {
    var components = URLComponents(string: "https://api.appstoreconnect.apple.com/v1/apps")!
    components.queryItems = [
        URLQueryItem(name: "filter[bundleId]", value: bundleID),
        URLQueryItem(name: "fields[apps]", value: "bundleId"),
        URLQueryItem(name: "limit", value: "2"),
    ]
    let json = try await requestJSON(from: components.url!, token: token)
    let apps = json["data"] as? [[String: Any]] ?? []
    guard apps.count == 1, let id = apps[0]["id"] as? String else {
        throw AppStoreConnectError(
            description:
                "Expected one App Store Connect app for bundle ID \(bundleID), found \(apps.count)."
        )
    }
    return id
}

private func highestBuildComponent(appID: String, token: String) async throws -> Int {
    var components = URLComponents(
        string: "https://api.appstoreconnect.apple.com/v1/apps/\(appID)/buildUploads"
    )!
    components.queryItems = [
        URLQueryItem(name: "filter[platform]", value: "IOS"),
        URLQueryItem(name: "fields[buildUploads]", value: "cfBundleVersion"),
        URLQueryItem(name: "limit", value: "200"),
    ]

    var nextURL: URL? = components.url
    var highest = 0

    while let url = nextURL {
        let json = try await requestJSON(from: url, token: token)
        let uploads = json["data"] as? [[String: Any]] ?? []

        for upload in uploads {
            guard
                let attributes = upload["attributes"] as? [String: Any],
                let version = attributes["cfBundleVersion"] as? String
            else {
                throw AppStoreConnectError(description: "A build upload has no CFBundleVersion.")
            }
            let components = version.split(separator: ".", omittingEmptySubsequences: false)
            guard
                1...3 ~= components.count,
                components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
                let first = components.first.flatMap({ Int($0) })
            else {
                throw AppStoreConnectError(
                    description: "Unsupported App Store build number: \(version)")
            }
            highest = max(highest, first)
        }

        let links = json["links"] as? [String: Any]
        nextURL = (links?["next"] as? String).flatMap(URL.init(string:))
    }

    guard highest < Int.max else {
        throw AppStoreConnectError(description: "The App Store build number cannot be incremented.")
    }
    return highest
}

private func startBuild(workflowID: String, token: String) async throws -> (number: Int, id: String)
{
    let url = URL(string: "https://api.appstoreconnect.apple.com/v1/ciBuildRuns")!
    let body: [String: Any] = [
        "data": [
            "type": "ciBuildRuns",
            "attributes": [:],
            "relationships": [
                "workflow": [
                    "data": [
                        "type": "ciWorkflows",
                        "id": workflowID,
                    ]
                ]
            ],
        ]
    ]

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw AppStoreConnectError(description: "App Store Connect returned an invalid response.")
    }
    guard httpResponse.statusCode == 201 else {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errors = json?["errors"] as? [[String: Any]]
        let detail = errors?.compactMap { $0["detail"] as? String }.joined(separator: " ")
        throw AppStoreConnectError(
            description:
                "App Store Connect returned HTTP \(httpResponse.statusCode). \(detail ?? "")"
                .trimmingCharacters(in: .whitespaces)
        )
    }
    guard
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let buildRun = json["data"] as? [String: Any],
        let id = buildRun["id"] as? String,
        let attributes = buildRun["attributes"] as? [String: Any],
        let number = attributes["number"] as? Int
    else {
        throw AppStoreConnectError(description: "App Store Connect returned invalid build data.")
    }
    return (number, id)
}

#if !APP_STORE_CONNECT_TESTS
    do {
        enum Operation: String {
            case nextBuildNumber = "next-build-number"
            case triggerBuild = "trigger-build"
        }
        guard CommandLine.arguments.count == 5,
            let operation = Operation(rawValue: CommandLine.arguments[1])
        else {
            throw AppStoreConnectError(
                description:
                    "Usage: app_store_connect.swift next-build-number BUNDLE_ID KEY_ID ISSUER_ID\n"
                    + "       app_store_connect.swift trigger-build WORKFLOW_ID KEY_ID ISSUER_ID")
        }
        let identifier = CommandLine.arguments[2]
        let keyID = CommandLine.arguments[3]
        let issuerID = CommandLine.arguments[4]
        if operation == .triggerBuild && UUID(uuidString: identifier) == nil {
            throw AppStoreConnectError(
                description: "Invalid Xcode Cloud workflow ID: \(identifier)")
        }
        let keyDirectory =
            ProcessInfo.processInfo.environment["API_PRIVATE_KEYS_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".appstoreconnect/private_keys", directoryHint: .isDirectory)
        let keyURL = keyDirectory.appending(path: "AuthKey_\(keyID).p8")
        guard FileManager.default.isReadableFile(atPath: keyURL.path) else {
            throw AppStoreConnectError(description: "Missing API key at \(keyURL.path)")
        }
        let token = try makeToken(keyID: keyID, issuerID: issuerID, keyURL: keyURL)
        switch operation {
        case .nextBuildNumber:
            let id = try await appID(bundleID: identifier, token: token)
            let highest = try await highestBuildComponent(appID: id, token: token)
            print(highest + 1)
        case .triggerBuild:
            let build = try await startBuild(workflowID: identifier, token: token)
            print("Started Xcode Cloud build #\(build.number) (ID: \(build.id)).")
        }
    } catch {
        FileHandle.standardError.write(Data("App Store Connect command failed: \(error)\n".utf8))
        exit(1)
    }
#endif
