import Foundation

private struct TokenTestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw TokenTestFailure(description: message)
    }
}

@discardableResult
private func runCommand(_ arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw TokenTestFailure(description: String(decoding: data, as: UTF8.self))
    }
    return data
}

#if SHEPHERD_TOKEN_TESTS

private func decodeBase64URL(_ value: String) -> Data? {
    var base64 = value
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder != 0 {
        base64 += String(repeating: "=", count: 4 - remainder)
    }
    return Data(base64Encoded: base64)
}

private func runAllTests() throws {
    // 1. Key path resolution prefers env override and falls back to default home path.
    let home = URL(fileURLWithPath: "/tmp/fake-home")
    try expect(
        resolveShepherdKeyURL(environment: [:], homeDirectory: home).path
            == "/tmp/fake-home/.clinical-github-apps/clinical-pr-shepherd.pem",
        "Default key path mismatch"
    )
    try expect(
        resolveShepherdKeyURL(
            environment: ["CLINICAL_PR_SHEPHERD_PRIVATE_KEY_PATH": "/custom/key.pem"],
            homeDirectory: home
        ).path == "/custom/key.pem",
        "Explicit key path override mismatch"
    )

    // 2. Generates a valid RS256 JWT verifiable with the matching RSA public key.
    let tempDir = FileManager.default.temporaryDirectory.appending(path: "shepherd-jwt-\(UUID())")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let privateKey = tempDir.appending(path: "private.pem")
    let publicKey = tempDir.appending(path: "public.pem")
    try runCommand(["openssl", "genrsa", "-out", privateKey.path, "2048"])
    try runCommand(["openssl", "rsa", "-in", privateKey.path, "-pubout", "-out", publicKey.path])

    let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
    let jwt = try makeGitHubAppJWT(appID: "5860740", keyURL: privateKey, now: fixedDate)
    let parts = jwt.split(separator: ".").map(String.init)
    try expect(parts.count == 3, "JWT must have 3 dot-separated segments")

    guard let headerData = decodeBase64URL(parts[0]),
          let payloadData = decodeBase64URL(parts[1]),
          let sigData = decodeBase64URL(parts[2]),
          let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
          let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
        throw TokenTestFailure(description: "Failed to decode JWT segments")
    }

    try expect(header["alg"] as? String == "RS256", "Expected alg=RS256")
    try expect(header["typ"] as? String == "JWT", "Expected typ=JWT")
    try expect(payload["iss"] as? String == "5860740", "Expected iss=5860740")
    try expect(payload["iat"] as? Int == 1_799_999_940, "Expected iat backdated by 60s")
    try expect(payload["exp"] as? Int == 1_800_000_540, "Expected exp +9m")

    // Verify RS256 signature using openssl against the generated public key.
    let signingInputFile = tempDir.appending(path: "input.txt")
    let sigFile = tempDir.appending(path: "sig.bin")
    try Data("\(parts[0]).\(parts[1])".utf8).write(to: signingInputFile)
    try sigData.write(to: sigFile)
    let verifyOut = try runCommand([
        "openssl", "dgst", "-sha256", "-verify", publicKey.path,
        "-signature", sigFile.path, signingInputFile.path,
    ])
    let verifyText = String(decoding: verifyOut, as: UTF8.self)
    try expect(verifyText.contains("Verified OK"), "Signature verification failed: \(verifyText)")
}

do {
    try runAllTests()
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}

#else

do {
    let testSource = URL(fileURLWithPath: #filePath)
    let scriptsDir = testSource.deletingLastPathComponent()
    let tempDir = FileManager.default.temporaryDirectory.appending(path: "shepherd-token-tests-\(UUID())")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let implementation = try String(contentsOf: scriptsDir.appending(path: "shepherd_token.swift"), encoding: .utf8)
    let tests = try String(contentsOf: testSource, encoding: .utf8)
    let combined = tempDir.appending(path: "shepherd_token_tests.swift")
    let binary = tempDir.appending(path: "shepherd_token_tests")
    try (implementation + "\n" + tests).write(to: combined, atomically: true, encoding: .utf8)

    try runCommand(["swiftc", "-D", "SHEPHERD_TOKEN_TESTS", combined.path, "-o", binary.path])
    try runCommand([binary.path])

    // Verify the real CLI compiles and reports a clear error when the key file is missing.
    let cli = tempDir.appending(path: "shepherd_token_cli")
    try runCommand(["swiftc", scriptsDir.appending(path: "shepherd_token.swift").path, "-o", cli.path])
    let missingPath = tempDir.appending(path: "does-not-exist.pem").path
    do {
        try runCommand(["env", "CLINICAL_PR_SHEPHERD_PRIVATE_KEY_PATH=\(missingPath)", cli.path])
        throw TokenTestFailure(description: "CLI succeeded with missing private key.")
    } catch let error as TokenTestFailure {
        try expect(error.description.contains("Private key not found"), error.description)
    }

    print("PASS shepherd_token: key resolution, RS256 JWT signature verification, and missing-key CLI check")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

#endif
