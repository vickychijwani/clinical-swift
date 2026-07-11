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

do {
    guard CommandLine.arguments.count == 4 else {
        throw AppStoreConnectError(
            description: "Usage: trigger_xcode_cloud_build.swift WORKFLOW_ID KEY_ID ISSUER_ID"
        )
    }

    let workflowID = CommandLine.arguments[1]
    let keyID = CommandLine.arguments[2]
    let issuerID = CommandLine.arguments[3]
    guard UUID(uuidString: workflowID) != nil else {
        throw AppStoreConnectError(description: "Invalid Xcode Cloud workflow ID: \(workflowID)")
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
    let build = try await startBuild(workflowID: workflowID, token: token)
    print("Started Xcode Cloud build #\(build.number) (ID: \(build.id)).")
} catch {
    FileHandle.standardError.write(Data("Unable to start Xcode Cloud build: \(error)\n".utf8))
    exit(1)
}
