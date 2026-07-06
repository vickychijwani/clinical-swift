import CryptoKit
import Foundation

private struct AppStoreConnectError: Error, CustomStringConvertible {
    let description: String
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacing("+", with: "-")
        .replacing("/", with: "_")
        .replacing("=", with: "")
}

private func makeToken(keyID: String, issuerID: String, keyURL: URL) throws -> String {
    let pem = try String(contentsOf: keyURL, encoding: .utf8)
    let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
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
    let signature = try key.signature(for: Data(signingInput.utf8))
    return "\(signingInput).\(base64URL(signature.rawRepresentation))"
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

do {
    guard CommandLine.arguments.count == 4 else {
        throw AppStoreConnectError(
            description: "Usage: next_app_store_build_number.swift BUNDLE_ID KEY_ID ISSUER_ID"
        )
    }

    let bundleID = CommandLine.arguments[1]
    let keyID = CommandLine.arguments[2]
    let issuerID = CommandLine.arguments[3]
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
    let id = try await appID(bundleID: bundleID, token: token)
    let highest = try await highestBuildComponent(appID: id, token: token)
    print(highest + 1)
} catch {
    FileHandle.standardError.write(Data("Unable to resolve the next build number: \(error)\n".utf8))
    exit(1)
}
