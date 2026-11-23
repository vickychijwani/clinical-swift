import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct AppStoreConnectError: Error, CustomStringConvertible {
    let description: String
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacing("+", with: "-")
        .replacing("/", with: "_")
        .replacing("=", with: "")
}

// OpenSSL emits DER integers. ES256 JWTs need two unsigned, 32-byte integers.
func jwtSignature(from der: Data) throws -> Data {
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

func sign(_ input: String, keyURL: URL) throws -> Data {
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

func makeToken(keyID: String, issuerID: String, keyURL: URL) throws -> String {
    struct Header: Encodable { let alg = "ES256", kid: String, typ = "JWT" }
    struct Payload: Encodable { let iss: String, iat: Int, exp: Int, aud = "appstoreconnect-v1" }
    let now = Int(Date().timeIntervalSince1970)
    let encoder = JSONEncoder()
    let header = try encoder.encode(Header(kid: keyID))
    let payload = try encoder.encode(Payload(iss: issuerID, iat: now, exp: now + 10 * 60))
    let signingInput = "\(base64URL(header)).\(base64URL(payload))"
    let signature = try sign(signingInput, keyURL: keyURL)
    return "\(signingInput).\(base64URL(signature))"
}

private struct APIErrorResponse: Decodable {
    struct Item: Decodable { let detail: String? }
    let errors: [Item]?
}

private struct ListResponse<Item: Decodable>: Decodable {
    struct Links: Decodable { let next: String? }
    let data: [Item]?
    let links: Links?
}

private func request<Response: Decodable>(
    _ url: URL,
    method: String = "GET",
    token: String,
    body: Data? = nil,
    expectedStatus: Range<Int> = 200..<300,
    invalidDataMessage: String = "App Store Connect returned invalid JSON."
) async throws -> Response {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body {
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw AppStoreConnectError(description: "App Store Connect returned an invalid response.")
    }
    guard expectedStatus ~= httpResponse.statusCode else {
        let detail = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?
            .errors?.compactMap(\.detail).joined(separator: " ")
        throw AppStoreConnectError(
            description:
                "App Store Connect returned HTTP \(httpResponse.statusCode). \(detail ?? "")"
                .trimmingCharacters(in: .whitespaces))
    }
    do {
        return try JSONDecoder().decode(Response.self, from: data)
    } catch {
        throw AppStoreConnectError(description: invalidDataMessage)
    }
}

private func appID(bundleID: String, token: String) async throws -> String {
    struct App: Decodable { let id: String }
    var components = URLComponents(string: "https://api.appstoreconnect.apple.com/v1/apps")!
    components.queryItems = [
        URLQueryItem(name: "filter[bundleId]", value: bundleID),
        URLQueryItem(name: "fields[apps]", value: "bundleId"),
        URLQueryItem(name: "limit", value: "2"),
    ]
    let apps = (try await request(components.url!, token: token) as ListResponse<App>).data ?? []
    guard apps.count == 1 else {
        throw AppStoreConnectError(
            description:
                "Expected one App Store Connect app for bundle ID \(bundleID), found \(apps.count)."
        )
    }
    return apps[0].id
}

private func highestBuildComponent(appID: String, token: String) async throws -> Int {
    struct Upload: Decodable {
        struct Attributes: Decodable { let cfBundleVersion: String? }
        let attributes: Attributes?
    }
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
        let response: ListResponse<Upload> = try await request(url, token: token)
        for upload in response.data ?? [] {
            guard let version = upload.attributes?.cfBundleVersion else {
                throw AppStoreConnectError(description: "A build upload has no CFBundleVersion.")
            }
            let parts = version.split(separator: ".", omittingEmptySubsequences: false)
            guard 1...3 ~= parts.count,
                parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
                let first = parts.first.flatMap({ Int($0) })
            else {
                throw AppStoreConnectError(
                    description: "Unsupported App Store build number: \(version)")
            }
            highest = max(highest, first)
        }
        nextURL = response.links?.next.flatMap(URL.init(string:))
    }

    guard highest < Int.max else {
        throw AppStoreConnectError(description: "The App Store build number cannot be incremented.")
    }
    return highest
}

private func startBuild(workflowID: String, token: String) async throws -> (number: Int, id: String)
{
    struct Ref: Encodable { let type = "ciWorkflows", id: String }
    struct Workflow: Encodable { let data: Ref }
    struct Relationships: Encodable { let workflow: Workflow }
    struct Payload: Encodable {
        let type = "ciBuildRuns", attributes: [String: String] = [:], relationships: Relationships
    }
    struct RequestBody: Encodable { let data: Payload }
    struct Response: Decodable {
        struct BuildRun: Decodable {
            struct Attributes: Decodable { let number: Int }
            let id: String
            let attributes: Attributes
        }
        let data: BuildRun
    }

    let url = URL(string: "https://api.appstoreconnect.apple.com/v1/ciBuildRuns")!
    let body = try JSONEncoder().encode(
        RequestBody(
            data: Payload(
                relationships: Relationships(workflow: Workflow(data: Ref(id: workflowID))))))
    let response: Response = try await request(
        url, method: "POST", token: token, body: body, expectedStatus: 201..<202,
        invalidDataMessage: "App Store Connect returned invalid build data.")
    return (response.data.attributes.number, response.data.id)
}

private func runCLI() async {
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
}

#if !SCRIPT_TESTS
    let _ = await runCLI()
#endif
