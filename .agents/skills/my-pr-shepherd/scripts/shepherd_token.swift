import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

let defaultShepherdAppID = "5860740"
let defaultShepherdInstallationID = "184306031"
let defaultShepherdKeyRelativePath = ".clinical-github-apps/clinical-pr-shepherd.pem"

struct ShepherdTokenError: Error, CustomStringConvertible {
    let description: String
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func resolveShepherdKeyURL(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) -> URL {
    if let explicit = environment["CLINICAL_PR_SHEPHERD_PRIVATE_KEY_PATH"], !explicit.isEmpty {
        let expanded = (explicit as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
    return homeDirectory.appending(path: defaultShepherdKeyRelativePath)
}

func signRS256(_ input: String, keyURL: URL) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["openssl", "dgst", "-sha256", "-sign", keyURL.path]
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    try process.run()
    try stdinPipe.fileHandleForWriting.write(contentsOf: Data(input.utf8))
    try stdinPipe.fileHandleForWriting.close()
    let signature = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let errText = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw ShepherdTokenError(
            description: "OpenSSL RS256 signing failed for \(keyURL.path): \(errText)"
        )
    }
    return signature
}

func makeGitHubAppJWT(
    appID: String,
    keyURL: URL,
    now: Date = Date()
) throws -> String {
    let timestamp = Int(now.timeIntervalSince1970)
    let header = try JSONSerialization.data(
        withJSONObject: ["alg": "RS256", "typ": "JWT"],
        options: [.sortedKeys]
    )
    // Backdate iat by 60s to tolerate clock drift with GitHub.
    let payload = try JSONSerialization.data(
        withJSONObject: [
            "exp": timestamp + 9 * 60,
            "iat": timestamp - 60,
            "iss": appID,
        ],
        options: [.sortedKeys]
    )
    let signingInput = "\(base64URL(header)).\(base64URL(payload))"
    let signature = try signRS256(signingInput, keyURL: keyURL)
    return "\(signingInput).\(base64URL(signature))"
}

#if !SHEPHERD_TOKEN_TESTS

func mintInstallationToken(appID: String, installationID: String, keyURL: URL) throws -> String {
    guard FileManager.default.fileExists(atPath: keyURL.path) else {
        throw ShepherdTokenError(
            description: """
                Private key not found at \(keyURL.path).
                Place the clinical-pr-shepherd .pem key there (chmod 600), or set CLINICAL_PR_SHEPHERD_PRIVATE_KEY_PATH.
                """
        )
    }

    let jwt = try makeGitHubAppJWT(appID: appID, keyURL: keyURL)
    let url = URL(string: "https://api.github.com/app/installations/\(installationID)/access_tokens")!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

    let semaphore = DispatchSemaphore(value: 0)
    var responseData: Data?
    var httpResponse: HTTPURLResponse?
    var requestError: Error?

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        responseData = data
        httpResponse = response as? HTTPURLResponse
        requestError = error
        semaphore.signal()
    }
    task.resume()
    semaphore.wait()

    if let requestError {
        throw ShepherdTokenError(description: "GitHub API request failed: \(requestError.localizedDescription)")
    }
    guard let httpResponse, let responseData else {
        throw ShepherdTokenError(description: "GitHub API returned an empty response.")
    }
    guard 200..<300 ~= httpResponse.statusCode else {
        let body = String(decoding: responseData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw ShepherdTokenError(
            description: "GitHub API returned HTTP \(httpResponse.statusCode): \(body)"
        )
    }
    guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
          let token = json["token"] as? String, !token.isEmpty else {
        throw ShepherdTokenError(description: "GitHub API response did not include an installation token.")
    }
    return token
}

do {
    let env = ProcessInfo.processInfo.environment
    let appID = env["CLINICAL_PR_SHEPHERD_APP_ID"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultShepherdAppID
    let installationID = env["CLINICAL_PR_SHEPHERD_INSTALLATION_ID"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultShepherdInstallationID
    let keyURL = resolveShepherdKeyURL(environment: env)
    let token = try mintInstallationToken(appID: appID, installationID: installationID, keyURL: keyURL)
    FileHandle.standardOutput.write(Data("\(token)\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

#endif
