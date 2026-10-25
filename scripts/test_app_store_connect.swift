import Foundation

private struct SigningTestError: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ value: Bool, _ message: String) throws {
    if !value { throw SigningTestError(description: message) }
}

@discardableResult
private func command(_ arguments: [String], environment: [String: String]? = nil) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    if let environment { process.environment = environment }
    process.standardInput = FileHandle.nullDevice
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw SigningTestError(description: String(decoding: data, as: UTF8.self))
    }
    return data
}

#if APP_STORE_CONNECT_TESTS
    private func decode(_ segment: Substring) throws -> Data {
        let base64 = segment.replacing("-", with: "+").replacing("_", with: "/")
        guard
            let data = Data(
                base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4))
        else { throw SigningTestError(description: "Invalid base64url in JWT.") }
        return data
    }

    private func derInteger(_ bytes: Data.SubSequence) -> [UInt8] {
        var integer = Array(bytes.drop(while: { $0 == 0 }))
        if integer.isEmpty { integer = [0] }
        if integer[0] >= 0x80 { integer.insert(0, at: 0) }
        return [0x02, UInt8(integer.count)] + integer
    }

    private func testSigning(in directory: URL) throws {
        // Cover short integers and the sign-padding byte that DER can add.
        for length in [1, 31, 32] {
            for highBit in [false, true] {
                let integer = [UInt8](repeating: highBit ? 0x80 : 0x01, count: length)
                let encoded = highBit ? [UInt8(0)] + integer : integer
                let field = [UInt8(0x02), UInt8(encoded.count)] + encoded
                let der = Data([0x30, UInt8(field.count * 2)] + field + field)
                let raw = try jwtSignature(from: der)
                let padded = [UInt8](repeating: 0, count: 32 - length) + integer
                try expect(raw == Data(padded + padded), "DER conversion changed the integers.")
            }
        }

        let valid: [UInt8] = [0x30, 6, 0x02, 1, 1, 0x02, 1, 1]
        let invalid: [[UInt8]] = [
            [], Array(valid.dropLast()), valid + [0],
            [0x31] + Array(valid.dropFirst()),
            [0x30, 6, 0x03, 1, 1, 0x02, 1, 1],
            [0x30, 6, 0x02, 0, 1, 0x02, 1, 1],
            [0x30, 6, 0x02, 1, 0x80, 0x02, 1, 1],
            [0x30, 7, 0x02, 2, 0, 1, 0x02, 1, 1],
            [0x30, 38, 0x02, 33] + [UInt8](repeating: 1, count: 33) + [0x02, 1, 1],
        ]
        for der in invalid {
            do {
                _ = try jwtSignature(from: Data(der))
                throw SigningTestError(description: "Invalid DER was accepted.")
            } catch is AppStoreConnectError {}
        }

        let key = directory.appending(path: "test key.p8")
        let publicKey = directory.appending(path: "public.pem")
        let badKey = directory.appending(path: "invalid.p8")
        try "not a private key".write(to: badKey, atomically: true, encoding: .utf8)
        try command([
            "openssl", "genpkey", "-algorithm", "EC", "-pkeyopt",
            "ec_paramgen_curve:P-256", "-out", key.path,
        ])
        try command(["openssl", "pkey", "-in", key.path, "-pubout", "-out", publicKey.path])
        do {
            _ = try sign("test", keyURL: badKey)
            throw SigningTestError(description: "Invalid key was accepted.")
        } catch is AppStoreConnectError {}

        for _ in 0..<10 {
            let token = try makeToken(keyID: "TEST_KEY", issuerID: "TEST_ISSUER", keyURL: key)
            let parts = token.split(separator: ".")
            try expect(parts.count == 3, "JWT must have three parts.")
            let header = try JSONDecoder().decode([String: String].self, from: decode(parts[0]))
            try expect(
                header == ["alg": "ES256", "kid": "TEST_KEY", "typ": "JWT"],
                "JWT header changed.")
            struct Claims: Decodable {
                let iss: String
                let aud: String
                let iat: Int
                let exp: Int
            }
            let claims = try JSONDecoder().decode(Claims.self, from: decode(parts[1]))
            try expect(claims.iss == "TEST_ISSUER", "JWT issuer changed.")
            try expect(claims.aud == "appstoreconnect-v1", "JWT audience changed.")
            try expect(claims.exp - claims.iat == 600, "JWT lifetime changed.")
            try expect(
                abs(Double(claims.iat) - Date().timeIntervalSince1970) < 30,
                "JWT issue time is not current.")
            let raw = try decode(parts[2])
            try expect(raw.count == 64, "ES256 signature must have 64 bytes.")
            let body = derInteger(raw.prefix(32)) + derInteger(raw.suffix(32))
            let signature = directory.appending(path: "signature.der")
            let input = directory.appending(path: "signing-input")
            try Data([0x30, UInt8(body.count)] + body).write(to: signature)
            try Data("\(parts[0]).\(parts[1])".utf8).write(to: input)
            try command([
                "openssl", "dgst", "-sha256", "-verify", publicKey.path,
                "-signature", signature.path, input.path,
            ])
        }
    }

    do {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        if CommandLine.arguments.contains("--missing-openssl") {
            do {
                _ = try sign("test", keyURL: directory.appending(path: "test key.p8"))
                throw SigningTestError(description: "Signing passed without OpenSSL.")
            } catch let error as AppStoreConnectError {
                try expect(
                    error.description.contains("OpenSSL signing failed"),
                    "Missing OpenSSL did not produce a useful error.")
            }
        } else {
            try testSigning(in: directory)
        }
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
#else
    do {
        let testSource = URL(fileURLWithPath: #filePath)
        let scripts = testSource.deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app store signing \(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tests = try String(contentsOf: testSource, encoding: .utf8)
        let name = "app_store_connect"
        let source = scripts.appending(path: name + ".swift")
        let combined = directory.appending(path: name + ".swift")
        let binary = directory.appending(path: name)
        let implementation = try String(contentsOf: source, encoding: .utf8)
        try (implementation + "\n" + tests).write(
            to: combined, atomically: true, encoding: .utf8)
        try command([
            "swiftc", "-D", "APP_STORE_CONNECT_TESTS", combined.path, "-o", binary.path,
        ])
        try command([binary.path, directory.path])
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = directory.appending(path: "missing tools").path
        try command(
            [binary.path, directory.path, "--missing-openssl"], environment: environment)
        // Check the actual command body too, without sending an API request.
        let cli = directory.appending(path: "app-store-connect-cli")
        try command(["swiftc", source.path, "-o", cli.path])
        for (arguments, message) in [
            ([], "Usage:"),
            (["unknown", "identifier", "KEY", "ISSUER"], "Usage:"),
            (["trigger-build", "invalid", "KEY", "ISSUER"], "Invalid Xcode Cloud workflow ID"),
            (["next-build-number", "in.bitehaus.clinical", "KEY", "ISSUER"], "Missing API key"),
        ] {
            var environment = ProcessInfo.processInfo.environment
            environment["API_PRIVATE_KEYS_DIR"] = directory.path
            do {
                try command([cli.path] + arguments, environment: environment)
                throw SigningTestError(description: "Invalid command was accepted.")
            } catch let error as SigningTestError {
                try expect(error.description.contains(message), error.description)
            }
        }
        print("PASS \(name): DER validation, JWT claims, signatures, and signing errors")
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
#endif
