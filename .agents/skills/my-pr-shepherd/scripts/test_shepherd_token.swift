import Foundation

private struct TokenTestFailure: Error, CustomStringConvertible { let description: String }

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw TokenTestFailure(description: message) }
}

@discardableResult
private func runCommand(_ arguments: [String]) throws -> Data {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = arguments
    p.standardInput = FileHandle.nullDevice
    let out = Pipe()
    p.standardOutput = out
    p.standardError = out
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw TokenTestFailure(description: String(decoding: data, as: UTF8.self)) }
    return data
}

#if SHEPHERD_TOKEN_TESTS

private func decodeBase64URL(_ value: String) -> Data? {
    var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let rem = s.count % 4
    if rem != 0 { s += String(repeating: "=", count: 4 - rem) }
    return Data(base64Encoded: s)
}

private func runAllTests() throws {
    let home = URL(fileURLWithPath: "/tmp/fake-home")
    try expect(resolveShepherdKeyURL(environment: [:], homeDirectory: home).path == "/tmp/fake-home/.clinical-github-apps/clinical-pr-shepherd.pem", "Default path mismatch")
    try expect(resolveShepherdKeyURL(environment: ["CLINICAL_PR_SHEPHERD_PRIVATE_KEY_PATH": "/custom/key.pem"], homeDirectory: home).path == "/custom/key.pem", "Env override mismatch")

    let tmp = FileManager.default.temporaryDirectory.appending(path: "shepherd-jwt-\(UUID())")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let priv = tmp.appending(path: "private.pem"), pub = tmp.appending(path: "public.pem")
    try runCommand(["openssl", "genrsa", "-out", priv.path, "2048"])
    try runCommand(["openssl", "rsa", "-in", priv.path, "-pubout", "-out", pub.path])

    let jwt = try makeGitHubAppJWT(appID: "5860740", keyURL: priv, now: Date(timeIntervalSince1970: 1_800_000_000))
    let parts = jwt.split(separator: ".").map(String.init)
    try expect(parts.count == 3, "JWT must have 3 parts")

    let header = try JSONSerialization.jsonObject(with: decodeBase64URL(parts[0])!) as? [String: Any]
    let payload = try JSONSerialization.jsonObject(with: decodeBase64URL(parts[1])!) as? [String: Any]
    try expect(header?["alg"] as? String == "RS256", "Expected RS256")
    try expect(payload?["iss"] as? String == "5860740", "Expected iss")
    try expect(payload?["iat"] as? Int == 1_799_999_940, "Expected iat -60s")
    try expect(payload?["exp"] as? Int == 1_800_000_540, "Expected exp +9m")

    // Verify RS256 signature using openssl against the generated public key.
    let inputFile = tmp.appending(path: "in.txt"), sigFile = tmp.appending(path: "sig.bin")
    try Data("\(parts[0]).\(parts[1])".utf8).write(to: inputFile)
    try decodeBase64URL(parts[2])!.write(to: sigFile)
    let verified = String(decoding: try runCommand(["openssl", "dgst", "-sha256", "-verify", pub.path, "-signature", sigFile.path, inputFile.path]), as: UTF8.self)
    try expect(verified.contains("Verified OK"), "Signature verification failed: \(verified)")
}

do { try runAllTests() } catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}

#else

do {
    let testSource = URL(fileURLWithPath: #filePath)
    let dir = testSource.deletingLastPathComponent()
    let tmp = FileManager.default.temporaryDirectory.appending(path: "shepherd-token-tests-\(UUID())")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let combined = tmp.appending(path: "combined.swift")
    let bin = tmp.appending(path: "tests")
    let impl = try String(contentsOf: dir.appending(path: "shepherd_token.swift"), encoding: .utf8)
    let tests = try String(contentsOf: testSource, encoding: .utf8)
    try (impl + "\n" + tests).write(to: combined, atomically: true, encoding: .utf8)
    try runCommand(["swiftc", "-D", "SHEPHERD_TOKEN_TESTS", combined.path, "-o", bin.path])
    try runCommand([bin.path])

    // Verify the real CLI compiles and reports a clear error when the key file is missing.
    let cli = tmp.appending(path: "cli")
    try runCommand(["swiftc", dir.appending(path: "shepherd_token.swift").path, "-o", cli.path])
    do {
        try runCommand(["env", "CLINICAL_PR_SHEPHERD_PRIVATE_KEY_PATH=\(tmp.appending(path: "missing.pem").path)", cli.path])
        throw TokenTestFailure(description: "CLI succeeded with missing key.")
    } catch let error as TokenTestFailure {
        try expect(error.description.contains("Private key not found"), error.description)
    }

    print("PASS shepherd_token")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

#endif
