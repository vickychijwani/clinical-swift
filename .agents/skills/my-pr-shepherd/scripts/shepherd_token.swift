import Foundation

let defaultShepherdAppID = "5860740"
let defaultShepherdInstallationID = "184306031"
let defaultShepherdKeyRelativePath = ".clinical-github-apps/clinical-pr-shepherd.pem"

struct ShepherdTokenError: Error, CustomStringConvertible { let description: String }

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
    if let path = environment["CLINICAL_PR_SHEPHERD_PRIVATE_KEY_PATH"], !path.isEmpty {
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
    return homeDirectory.appending(path: defaultShepherdKeyRelativePath)
}

func runTool(_ executable: String, _ args: [String], stdin: Data? = nil) throws -> Data {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = [executable] + args
    let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
    p.standardInput = stdin == nil ? FileHandle.nullDevice : inPipe
    p.standardOutput = outPipe
    p.standardError = errPipe
    try p.run()
    if let stdin {
        try inPipe.fileHandleForWriting.write(contentsOf: stdin)
        try inPipe.fileHandleForWriting.close()
    }
    let out = outPipe.fileHandleForReading.readDataToEndOfFile()
    let err = errPipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        throw ShepherdTokenError(description: "\(executable) failed: \(String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    return out
}

func makeGitHubAppJWT(appID: String, keyURL: URL, now: Date = Date()) throws -> String {
    let ts = Int(now.timeIntervalSince1970)
    let header = try JSONSerialization.data(withJSONObject: ["alg": "RS256", "typ": "JWT"], options: [.sortedKeys])
    // Backdate iat by 60s to tolerate clock drift with GitHub.
    let payload = try JSONSerialization.data(withJSONObject: ["exp": ts + 9 * 60, "iat": ts - 60, "iss": appID], options: [.sortedKeys])
    let input = "\(base64URL(header)).\(base64URL(payload))"
    let sig = try runTool("openssl", ["dgst", "-sha256", "-sign", keyURL.path], stdin: Data(input.utf8))
    return "\(input).\(base64URL(sig))"
}

#if !SHEPHERD_TOKEN_TESTS

struct TokenResponse: Decodable { let token: String }

do {
    let env = ProcessInfo.processInfo.environment
    let appID = env["CLINICAL_PR_SHEPHERD_APP_ID"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultShepherdAppID
    let installID = env["CLINICAL_PR_SHEPHERD_INSTALLATION_ID"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultShepherdInstallationID
    let keyURL = resolveShepherdKeyURL(environment: env)
    guard FileManager.default.fileExists(atPath: keyURL.path) else {
        throw ShepherdTokenError(description: "Private key not found at \(keyURL.path). Place the clinical-pr-shepherd .pem key there (chmod 600), or set CLINICAL_PR_SHEPHERD_PRIVATE_KEY_PATH.")
    }

    let jwt = try makeGitHubAppJWT(appID: appID, keyURL: keyURL)
    let raw = try runTool("curl", [
        "-sS", "-w", "\n%{http_code}", "-X", "POST",
        "-H", "Authorization: Bearer \(jwt)",
        "-H", "Accept: application/vnd.github+json",
        "-H", "X-GitHub-Api-Version: 2022-11-28",
        "https://api.github.com/app/installations/\(installID)/access_tokens",
    ])
    let text = String(decoding: raw, as: UTF8.self)
    let split = text.lastIndex(of: "\n") ?? text.startIndex
    let body = String(text[..<split])
    let status = Int(text[text.index(after: split)...].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    guard 200..<300 ~= status else {
        throw ShepherdTokenError(description: "GitHub API returned HTTP \(status): \(body)")
    }
    let token = try JSONDecoder().decode(TokenResponse.self, from: Data(body.utf8)).token
    FileHandle.standardOutput.write(Data("\(token)\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

#endif
