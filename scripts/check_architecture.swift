import Foundation

struct ArchitectureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct LayerPolicy {
    let imports: Set<String>
    let dependencies: Set<String>
}

// ARCHITECTURE POLICY — EXPLICIT HUMAN APPROVAL REQUIRED
//
// These rules protect clear ownership and dependency boundaries.
// Passing the check is necessary, but does not prove a sound design.
//
// Do not change rules, add exceptions, or disable checks merely to pass.
// Do not bypass a boundary by copying existing logic, adding a parallel
// implementation, or moving code where the checker cannot detect it.
//
// First, look for a solution that preserves shared ownership and satisfies
// the existing boundaries. Do not force a solution that adds duplication
// or unnecessary complexity.
//
// If the boundary prevents a clean solution, report the conflict and
// propose the smallest code or policy change. Obtain explicit human
// approval before changing the policy. A feature or refactor request
// does not itself authorize that change.
//
// Keep approved policy changes separate from feature or refactor changes,
// so the human reviewer can inspect them directly.
enum ArchitecturePolicy {
    static let layers: [String: LayerPolicy] = [
        "ClinicalModels": LayerPolicy(
            imports: ["Foundation", "Dependencies"],
            dependencies: ["swift-dependencies/Dependencies"]),
        "ClinicalPersistence": LayerPolicy(
            imports: [
                "ClinicalModels", "Foundation", "Dependencies", "SQLiteData", "GRDB",
                "StructuredQueriesSQLite",
            ],
            dependencies: [
                "ClinicalModels", "swift-dependencies/Dependencies", "sqlite-data/SQLiteData",
                "grdb.swift/GRDB", "swift-structured-queries/StructuredQueriesSQLite",
            ]),
        "ClinicalDataTests": LayerPolicy(
            imports: [
                "ClinicalModels", "ClinicalPersistence", "Foundation", "Testing", "Dependencies",
                "GRDB", "SQLiteData",
            ],
            dependencies: [
                "ClinicalModels", "ClinicalPersistence", "swift-dependencies/Dependencies",
                "grdb.swift/GRDB", "sqlite-data/SQLiteData",
            ]),
    ]
    static let persistenceImports: Set<String> = [
        "ClinicalPersistence", "SQLiteData", "GRDB", "StructuredQueriesSQLite", "SQLite3",
    ]
    static let widgetForbiddenImports: Set<String> = [
        "ClinicalPersistence", "SQLiteData", "StructuredQueriesSQLite",
    ]
    static let targetRoots: [String: Set<String>] = [
        "clinical-swift": ["clinical-swift", "ClinicalShared"],
        "ClinicalWidgetExtension": ["ClinicalWidget", "ClinicalShared"],
        "clinical-swiftTests": ["clinical-swiftTests"],
        "clinical-swiftBackupTests": ["clinical-swiftBackupTests"],
        "clinical-swiftUITests": ["clinical-swiftUITests"],
    ]
    // Outer screens own observed queries. Their child display components receive domain values.
    static let queryScreens: Set<String> = [
        "clinical-swift/appointments/views/ScheduleEditorSheet.swift",
        "clinical-swift/patients/views/PatientDetailsView.swift",
        "clinical-swift/patients/views/PatientsView.swift",
    ]
    // These files import SQLiteData for preview dependency setup, not for display inputs.
    static let previewScreens: Set<String> = [
        "clinical-swift/appointments/views/ScheduleView.swift",
        "clinical-swift/appointments/views/AppointmentDetailsView.swift",
        "clinical-swift/appointments/views/AppointmentMessageView.swift",
        "clinical-swift/patients/views/EditPatientView.swift",
    ]
    static let sharedInfrastructure: Set<String> = [
        "ClinicalShared/ClinicalSharedDatabase.swift",
        "ClinicalShared/ClinicalDatabaseAccess.swift",
        "ClinicalShared/WidgetScheduleRepository.swift",
    ]
    static func isDisplay(_ path: String) -> Bool {
        path.contains("/views/") || path.hasPrefix("clinical-swift/widgets/")
            || path.hasPrefix("ClinicalShared/") && !sharedInfrastructure.contains(path)
            || path == "clinical-swift/backups/BackupSettingsSections.swift"
            || path == "clinical-swift/backups/BackupWarningToolbar.swift"
            || path == "clinical-swift/telemetry/DiagnosticsSettingsSection.swift"
    }
}

struct ImportToken: Equatable {
    let module: String
    let line: Int
}

// Scan every conditional branch. Erase comments and strings before reading import tokens.
func sourceImports(_ source: String) -> [ImportToken] {
    let bytes = Array(source.utf8)
    var offset = 0
    var line = 1
    var tokens: [(text: String, line: Int)] = []
    func matches(_ marker: String) -> Bool {
        let utf8 = marker.utf8
        let count = utf8.count
        return offset + count <= bytes.count
            && bytes[offset..<(offset + count)].elementsEqual(utf8)
    }
    func advance(_ count: Int = 1) {
        let end = min(bytes.count, offset + count)
        line += bytes[offset..<end].filter { $0 == 10 }.count
        offset = end
    }
    func identifier(_ value: UInt8) -> Bool {
        value >= 65 && value <= 90 || value >= 97 && value <= 122
            || value >= 48 && value <= 57 || value == 95 || value >= 128
    }
    func skipComment() -> Bool {
        if matches("//") {
            while offset < bytes.count && bytes[offset] != 10 { advance() }
            return true
        }
        guard matches("/*") else { return false }
        advance(2)
        var depth = 1
        while offset < bytes.count && depth > 0 {
            if matches("/*") {
                depth += 1
                advance(2)
            } else if matches("*/") {
                depth -= 1
                advance(2)
            } else {
                advance()
            }
        }
        return true
    }
    func skipString() -> Bool {
        var quote = offset
        while quote < bytes.count && bytes[quote] == 35 { quote += 1 }
        guard quote < bytes.count && bytes[quote] == 34 else { return false }
        let hashes = quote - offset
        advance(hashes)
        let delimiter = matches("\"\"\"") ? "\"\"\"" : "\""
        let closing = delimiter + String(repeating: "#", count: hashes)
        let escape = "\\" + String(repeating: "#", count: hashes)
        advance(delimiter.utf8.count)
        while offset < bytes.count {
            if matches(escape + "(") {
                advance(escape.utf8.count + 1)
                var depth = 1
                while offset < bytes.count && depth > 0 {
                    if skipComment() || skipString() { continue }
                    if matches("(") { depth += 1 }
                    if matches(")") { depth -= 1 }
                    advance()
                }
            } else if matches(escape) {
                advance(escape.utf8.count + 1)
            } else if matches(closing) {
                advance(closing.utf8.count)
                break
            } else {
                advance()
            }
        }
        return true
    }
    while offset < bytes.count {
        if skipComment() { continue }
        if skipString() {
            tokens.append(("<string>", line))
        } else if bytes[offset] == 96 {
            advance()
            let start = offset
            let tokenLine = line
            while offset < bytes.count && bytes[offset] != 96 { advance() }
            tokens.append(
                ("`" + String(decoding: bytes[start..<offset], as: UTF8.self) + "`", tokenLine))
            advance()
        } else if identifier(bytes[offset]) {
            let start = offset
            let tokenLine = line
            while offset < bytes.count && identifier(bytes[offset]) { advance() }
            tokens.append((String(decoding: bytes[start..<offset], as: UTF8.self), tokenLine))
        } else if bytes[offset] == 32 || bytes[offset] == 9 || bytes[offset] == 10
            || bytes[offset] == 13
        {
            advance()
        } else {
            tokens.append((String(UnicodeScalar(bytes[offset])), line))
            advance()
        }
    }
    let scopes: Set<String> = [
        "typealias", "struct", "class", "enum", "protocol", "let", "var", "func",
    ]
    var result: [ImportToken] = []
    for index in tokens.indices where tokens[index].text == "import" {
        var next = index + 1
        if next < tokens.count && scopes.contains(tokens[next].text) { next += 1 }
        if next < tokens.count {
            result.append(
                ImportToken(
                    module: tokens[next].text.trimmingCharacters(
                        in: CharacterSet(charactersIn: "`")), line: tokens[index].line))
        }
    }
    return result
}

func checkImports(path: String, source: String, widgetMember: Bool = false) -> [String] {
    var failures: [String] = []
    let layer = ArchitecturePolicy.layers.keys.first {
        path.hasPrefix(($0 == "ClinicalDataTests" ? "Tests/" : "Sources/") + $0 + "/")
    }
    for item in sourceImports(source) {
        func fail(_ rule: String) {
            failures.append("\(path):\(item.line): import \(item.module) violates \(rule)")
        }
        if let layer, let policy = ArchitecturePolicy.layers[layer],
            !policy.imports.contains(item.module)
        {
            fail("\(layer) allowed imports: \(policy.imports.sorted().joined(separator: ", "))")
        }
        if widgetMember || path.hasPrefix("ClinicalWidget/") || path.hasPrefix("ClinicalShared/"),
            ArchitecturePolicy.widgetForbiddenImports.contains(item.module)
        {
            fail(
                "widget and shared sources must remain read-only clients without ClinicalPersistence"
            )
        }
        if ArchitecturePolicy.isDisplay(path),
            ArchitecturePolicy.persistenceImports.contains(item.module)
        {
            let isQuery = ArchitecturePolicy.queryScreens.contains(path)
            let isPreview =
                ArchitecturePolicy.previewScreens.contains(path) && item.module == "SQLiteData"
            if !isQuery && !isPreview {
                fail("display components receive domain values and action closures")
            }
        }
    }
    return failures
}

func command(_ root: URL, _ executable: String, _ arguments: [String]) throws -> Data {
    let process = Process()
    process.currentDirectoryURL = root
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.standardInput = FileHandle.nullDevice
    let output = Pipe()
    // Keep diagnostics separate so they cannot corrupt JSON on stdout.
    process.standardOutput = output
    process.standardError = FileHandle.standardError
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ArchitectureError(
            "\(executable) \(arguments.joined(separator: " ")) failed (\(process.terminationStatus))"
        )
    }
    return data
}

struct PackageGraph: Decodable {
    struct Target: Decodable {
        let name: String
        var path: String?
        let sources: [String]?
        let exclude: [String]?
        var dependencies: [Dependency]
    }
    struct Product: Decodable {
        let name: String
        let targets: [String]
    }
    enum Dependency: Decodable {
        case product(name: String, package: String, hasModuleAliases: Bool)
        case name(String)

        enum CodingKeys: String, CodingKey { case product, byName, target }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if var array = try? container.nestedUnkeyedContainer(forKey: .product) {
                let name = try array.decode(String.self)
                let package = try array.decode(String.self)
                let hasAliases = try !array.isAtEnd && !array.decodeNil()
                self = .product(name: name, package: package, hasModuleAliases: hasAliases)
            } else if var array = try? container.nestedUnkeyedContainer(forKey: .byName) {
                self = .name(try array.decode(String.self))
            } else if var array = try? container.nestedUnkeyedContainer(forKey: .target) {
                self = .name(try array.decode(String.self))
            } else {
                throw ArchitectureError("Package.swift:1: Cannot read target dependency")
            }
        }
    }
    var targets: [Target]
    var products: [Product]
}

func packageGraph(_ root: URL) throws -> PackageGraph {
    let snapshot = FileManager.default.temporaryDirectory.appending(
        path: "clinical-package-\(UUID())")
    try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: snapshot) }
    // SwiftPM can rewrite platform-specific pins even when only reading the manifest.
    try FileManager.default.copyItem(
        at: root.appending(path: "Package.swift"), to: snapshot.appending(path: "Package.swift"))
    return try JSONDecoder().decode(
        PackageGraph.self, from: command(snapshot, "swift", ["package", "dump-package"]))
}

func checkPackage(_ graph: PackageGraph) throws -> [String] {
    var failures: [String] = []
    let names = Set(graph.targets.map(\.name))
    if names != Set(ArchitecturePolicy.layers.keys) {
        failures.append(
            "Package.swift:1: target set \(names.sorted()) violates the three-target package boundary"
        )
    }
    for target in graph.targets {
        guard let policy = ArchitecturePolicy.layers[target.name] else {
            failures.append("Package.swift:1: unknown target \(target.name)")
            continue
        }
        let expectedPath =
            (target.name == "ClinicalDataTests" ? "Tests/" : "Sources/") + target.name
        if let path = target.path, path != expectedPath {
            failures.append(
                "Package.swift:1: \(target.name) path \(path) violates standard layout \(expectedPath)"
            )
        }
        if target.sources != nil || !(target.exclude ?? []).isEmpty {
            failures.append(
                "Package.swift:1: \(target.name) must compile the full standard source folder")
        }
        for dependency in target.dependencies {
            let key: String
            switch dependency {
            case .product(let name, let package, let hasModuleAliases):
                key = package.lowercased() + "/" + name
                if hasModuleAliases {
                    failures.append(
                        "Package.swift:1: module aliases violate the explicit dependency policy")
                }
            case .name(let name):
                key = name
            }
            if !policy.dependencies.contains(key) {
                failures.append(
                    "Package.swift:1: \(target.name) dependency \(key) violates allowed dependencies \(policy.dependencies.sorted())"
                )
            }
        }
    }
    if Set(graph.products.map(\.name)) != ["ClinicalModels", "ClinicalPersistence"] {
        failures.append(
            "Package.swift:1: products must expose only ClinicalModels and ClinicalPersistence")
    }
    for product in graph.products where product.targets != [product.name] {
        failures.append("Package.swift:1: product \(product.name) must expose only its own target")
    }
    return failures
}

let projectPath = "clinical-swift.xcodeproj/project.pbxproj"

enum OpenStepPlistValue: Equatable {
    case string(String)
    case array([OpenStepPlistValue])
    case dictionary([String: OpenStepPlistValue])
    case data(Data)
}

// Parse OpenStep ASCII property lists (used by Xcode project.pbxproj) without macOS plutil
// so project membership checks run identically on Linux and macOS.
func parseOpenStepPlist(_ data: Data) throws -> OpenStepPlistValue {
    let bytes = Array(data)
    var offset = 0
    // Skip optional UTF-8 BOM.
    if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
        offset = 3
    }

    func fail(_ message: String) -> ArchitectureError {
        ArchitectureError("Invalid OpenStep plist at byte \(offset): \(message)")
    }

    func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0B || byte == 0x0C
    }

    func isUnquotedChar(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A)  // A-Z
            || (byte >= 0x61 && byte <= 0x7A)  // a-z
            || (byte >= 0x30 && byte <= 0x39)  // 0-9
            || byte == 0x5F  // _
            || byte == 0x24  // $
            || byte == 0x2F  // /
            || byte == 0x3A  // :
            || byte == 0x2E  // .
            || byte == 0x2D  // -
    }

    func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }

    func skipTrivia() throws {
        while offset < bytes.count {
            let byte = bytes[offset]
            if isWhitespace(byte) {
                offset += 1
            } else if byte == 0x2F && offset + 1 < bytes.count && bytes[offset + 1] == 0x2F {
                offset += 2
                while offset < bytes.count && bytes[offset] != 0x0A && bytes[offset] != 0x0D {
                    offset += 1
                }
            } else if byte == 0x2F && offset + 1 < bytes.count && bytes[offset + 1] == 0x2A {
                offset += 2
                var closed = false
                while offset + 1 < bytes.count {
                    if bytes[offset] == 0x2A && bytes[offset + 1] == 0x2F {
                        offset += 2
                        closed = true
                        break
                    }
                    offset += 1
                }
                if !closed { throw fail("unterminated block comment") }
            } else {
                break
            }
        }
    }

    func readHex16() throws -> UInt16 {
        guard offset + 4 <= bytes.count else { throw fail("truncated \\U escape") }
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let digit = hexValue(bytes[offset]) else {
                throw fail("invalid hex digit in \\U escape")
            }
            value = (value << 4) | UInt16(digit)
            offset += 1
        }
        return value
    }

    func parseQuotedString() throws -> String {
        let quote = bytes[offset]
        offset += 1
        var out: [UInt8] = []
        while offset < bytes.count {
            let byte = bytes[offset]
            if byte == quote {
                offset += 1
                guard let text = String(bytes: out, encoding: .utf8) else {
                    throw fail("invalid UTF-8 in quoted string")
                }
                return text
            }
            if byte == 0x5C {  // backslash
                offset += 1
                guard offset < bytes.count else { throw fail("unterminated escape sequence") }
                let esc = bytes[offset]
                switch esc {
                case 0x6E:  // n
                    out.append(0x0A)
                    offset += 1
                case 0x72:  // r
                    out.append(0x0D)
                    offset += 1
                case 0x74:  // t
                    out.append(0x09)
                    offset += 1
                case 0x61:  // a
                    out.append(0x07)
                    offset += 1
                case 0x62:  // b
                    out.append(0x08)
                    offset += 1
                case 0x66:  // f
                    out.append(0x0C)
                    offset += 1
                case 0x76:  // v
                    out.append(0x0B)
                    offset += 1
                case 0x55:  // Uxxxx
                    offset += 1
                    let unit = try readHex16()
                    if (0xD800...0xDBFF).contains(unit),
                        offset + 2 <= bytes.count,
                        bytes[offset] == 0x5C, bytes[offset + 1] == 0x55
                    {
                        offset += 2
                        let low = try readHex16()
                        guard (0xDC00...0xDFFF).contains(low) else {
                            throw fail("invalid UTF-16 low surrogate")
                        }
                        let codePoint =
                            0x10000 + ((UInt32(unit - 0xD800) << 10) | UInt32(low - 0xDC00))
                        guard let scalar = UnicodeScalar(codePoint) else {
                            throw fail("invalid Unicode scalar")
                        }
                        out.append(contentsOf: String(scalar).utf8)
                    } else {
                        guard let scalar = UnicodeScalar(UInt32(unit)) else {
                            throw fail("unpaired UTF-16 surrogate")
                        }
                        out.append(contentsOf: String(scalar).utf8)
                    }
                case 0x30...0x37:  // octal \ooo (up to 3 digits, decoded via legacy NeXTSTEP encoding to match plutil)
                    var value: UInt32 = 0
                    for _ in 0..<3 {
                        guard offset < bytes.count, (0x30...0x37).contains(bytes[offset]) else {
                            break
                        }
                        value = (value << 3) | UInt32(bytes[offset] - 0x30)
                        offset += 1
                    }
                    let scalar: UnicodeScalar
                    if value < 0x80, let ascii = UnicodeScalar(value) {
                        scalar = ascii
                    } else if value >= 0x80 && value <= 0xFD,
                        let mapped = UnicodeScalar(nextStepHighBytes[Int(value - 0x80)])
                    {
                        scalar = mapped
                    } else {
                        throw fail("invalid octal escape")
                    }
                    out.append(contentsOf: String(scalar).utf8)
                default:
                    out.append(esc)
                    offset += 1
                }
            } else {
                out.append(byte)
                offset += 1
            }
        }
        throw fail("unterminated quoted string")
    }

    // Legacy NeXTSTEP encoding for octal escape bytes 0x80...0xFD (matches CoreFoundation / plutil).
    let nextStepHighBytes: [UInt32] = [
        0x00A0, 0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C4, 0x00C5, 0x00C7,
        0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x00CC, 0x00CD, 0x00CE, 0x00CF,
        0x00D0, 0x00D1, 0x00D2, 0x00D3, 0x00D4, 0x00D5, 0x00D6, 0x00D9,
        0x00DA, 0x00DB, 0x00DC, 0x00DD, 0x00DE, 0x00B5, 0x00D7, 0x00F7,
        0x00A9, 0x00A1, 0x00A2, 0x00A3, 0x2044, 0x00A5, 0x0192, 0x00A7,
        0x00A4, 0x2019, 0x201C, 0x00AB, 0x2039, 0x203A, 0xFB01, 0xFB02,
        0x00AE, 0x2013, 0x2020, 0x2021, 0x00B7, 0x00A6, 0x00B6, 0x2022,
        0x201A, 0x201E, 0x201D, 0x00BB, 0x2026, 0x2030, 0x00AC, 0x00BF,
        0x00B9, 0x02CB, 0x00B4, 0x02C6, 0x02DC, 0x00AF, 0x02D8, 0x02D9,
        0x00A8, 0x00B2, 0x02DA, 0x00B8, 0x00B3, 0x02DD, 0x02DB, 0x02C7,
        0x2014, 0x00B1, 0x00BC, 0x00BD, 0x00BE, 0x00E0, 0x00E1, 0x00E2,
        0x00E3, 0x00E4, 0x00E5, 0x00E7, 0x00E8, 0x00E9, 0x00EA, 0x00EB,
        0x00EC, 0x00C6, 0x00ED, 0x00AA, 0x00EE, 0x00EF, 0x00F0, 0x00F1,
        0x0141, 0x00D8, 0x0152, 0x00BA, 0x00F2, 0x00F3, 0x00F4, 0x00F5,
        0x00F6, 0x00E6, 0x00F9, 0x00FA, 0x00FB, 0x0131, 0x00FC, 0x00FD,
        0x0142, 0x00F8, 0x0153, 0x00DF, 0x00FE, 0x00FF,
    ]

    func parseString() throws -> String {
        try skipTrivia()
        guard offset < bytes.count else { throw fail("expected string") }
        if bytes[offset] == 0x22 || bytes[offset] == 0x27 {
            return try parseQuotedString()
        }
        let start = offset
        while offset < bytes.count && isUnquotedChar(bytes[offset]) {
            offset += 1
        }
        guard offset > start else { throw fail("unexpected byte \(bytes[offset])") }
        return String(decoding: bytes[start..<offset], as: UTF8.self)
    }

    func parseData() throws -> Data {
        offset += 1  // skip '<'
        var raw = Data()
        var highNibble: UInt8?
        while offset < bytes.count {
            let byte = bytes[offset]
            if byte == 0x3E {  // '>'
                offset += 1
                guard highNibble == nil else { throw fail("odd number of hex digits in data") }
                return raw
            }
            if isWhitespace(byte) {
                offset += 1
                continue
            }
            guard let nibble = hexValue(byte) else {
                throw fail("invalid hex character in data")
            }
            offset += 1
            if let high = highNibble {
                raw.append((high << 4) | nibble)
                highNibble = nil
            } else {
                highNibble = nibble
            }
        }
        throw fail("unterminated data literal")
    }

    func parseValue() throws -> OpenStepPlistValue {
        try skipTrivia()
        guard offset < bytes.count else { throw fail("unexpected end of input") }
        switch bytes[offset] {
        case 0x7B:  // '{'
            offset += 1
            var dict: [String: OpenStepPlistValue] = [:]
            while true {
                try skipTrivia()
                guard offset < bytes.count else { throw fail("unterminated dictionary") }
                if bytes[offset] == 0x7D {  // '}'
                    offset += 1
                    return .dictionary(dict)
                }
                let key = try parseString()
                try skipTrivia()
                guard offset < bytes.count && bytes[offset] == 0x3D else {  // '='
                    throw fail("expected '=' after dictionary key \(key)")
                }
                offset += 1
                let value = try parseValue()
                try skipTrivia()
                guard offset < bytes.count && bytes[offset] == 0x3B else {  // ';'
                    throw fail("expected ';' after dictionary value for \(key)")
                }
                offset += 1
                dict[key] = value
            }
        case 0x28:  // '('
            offset += 1
            var items: [OpenStepPlistValue] = []
            while true {
                try skipTrivia()
                guard offset < bytes.count else { throw fail("unterminated array") }
                if bytes[offset] == 0x29 {  // ')'
                    offset += 1
                    return .array(items)
                }
                items.append(try parseValue())
                try skipTrivia()
                guard offset < bytes.count else { throw fail("unterminated array") }
                if bytes[offset] == 0x2C {  // ','
                    offset += 1
                } else if bytes[offset] == 0x29 {  // ')'
                    offset += 1
                    return .array(items)
                } else {
                    throw fail("expected ',' or ')' in array")
                }
            }
        case 0x3C:  // '<'
            return .data(try parseData())
        default:
            return .string(try parseString())
        }
    }

    let root = try parseValue()
    try skipTrivia()
    guard offset == bytes.count else { throw fail("trailing content after root value") }
    return root
}

struct XcodeProject: Equatable {
    struct Object: Equatable {
        var isa: String?
        var mainGroup: String?
        var sourceTree: String?
        var path: String?
        var children: [String]?
        var name: String?
        var packageProductDependencies: [String]?
        var buildPhases: [String]?
        var files: [String]?
        var productRef: String?
        var fileRef: String?
        var fileSystemSynchronizedGroups: [String]?
        var exceptions: [String]?
        var target: String?
        var membershipExceptions: [String]?
        var dependencies: [String]?
        var productName: String?

        init(plist value: OpenStepPlistValue, id: String) throws {
            guard case .dictionary(let fields) = value else {
                throw ArchitectureError("\(projectPath):1: Object \(id) must be a dictionary")
            }
            func stringField(_ key: String) throws -> String? {
                guard let raw = fields[key] else { return nil }
                guard case .string(let text) = raw else {
                    throw ArchitectureError("\(projectPath):1: \(id).\(key) must be a string")
                }
                return text
            }
            func stringArrayField(_ key: String) throws -> [String]? {
                guard let raw = fields[key] else { return nil }
                guard case .array(let items) = raw else {
                    throw ArchitectureError("\(projectPath):1: \(id).\(key) must be an array")
                }
                return try items.map { item in
                    guard case .string(let text) = item else {
                        throw ArchitectureError(
                            "\(projectPath):1: \(id).\(key) must contain strings")
                    }
                    return text
                }
            }
            self.isa = try stringField("isa")
            self.mainGroup = try stringField("mainGroup")
            self.sourceTree = try stringField("sourceTree")
            self.path = try stringField("path")
            self.children = try stringArrayField("children")
            self.name = try stringField("name")
            self.packageProductDependencies = try stringArrayField("packageProductDependencies")
            self.buildPhases = try stringArrayField("buildPhases")
            self.files = try stringArrayField("files")
            self.productRef = try stringField("productRef")
            self.fileRef = try stringField("fileRef")
            self.fileSystemSynchronizedGroups = try stringArrayField("fileSystemSynchronizedGroups")
            self.exceptions = try stringArrayField("exceptions")
            self.target = try stringField("target")
            self.membershipExceptions = try stringArrayField("membershipExceptions")
            self.dependencies = try stringArrayField("dependencies")
            self.productName = try stringField("productName")
        }
    }
    var rootObject: String
    var objects: [String: Object]

    init(plist value: OpenStepPlistValue) throws {
        guard case .dictionary(let root) = value,
            case .string(let rootObject) = root["rootObject"],
            case .dictionary(let rawObjects) = root["objects"]
        else {
            throw ArchitectureError(
                "\(projectPath):1: Cannot read Xcode project rootObject and objects")
        }
        self.rootObject = rootObject
        var decoded: [String: Object] = [:]
        decoded.reserveCapacity(rawObjects.count)
        for (id, rawObject) in rawObjects {
            decoded[id] = try Object(plist: rawObject, id: id)
        }
        self.objects = decoded
    }
}

func loadXcodeProject(at url: URL) throws -> XcodeProject {
    let data = try Data(contentsOf: url)
    return try XcodeProject(plist: try parseOpenStepPlist(data))
}

struct ProjectMembership {
    var widgetSources: Set<String> = []
    var failures: [String] = []
}

func checkProject(_ project: XcodeProject, paths: [String]) throws -> ProjectMembership {
    let objects = project.objects
    guard let mainGroup = objects[project.rootObject]?.mainGroup else {
        throw ArchitectureError(
            "\(projectPath):1: Cannot read Xcode project objects and main group")
    }
    var result = ProjectMembership()
    func fail(_ message: String) { result.failures.append("\(projectPath):1: \(message)") }
    var resolvedPaths: [String: String] = [:]
    func visit(_ id: String, parent: String, ancestors: Set<String>) throws {
        guard let object = objects[id], !ancestors.contains(id) else {
            throw ArchitectureError("\(projectPath):1: Missing or cyclic file/group \(id)")
        }
        let tree = object.sourceTree ?? "<group>"
        let path = object.path ?? ""
        let value =
            tree == "SOURCE_ROOT"
            ? path : [parent, path].filter { !$0.isEmpty }.joined(separator: "/")
        resolvedPaths[id] = value
        for child in object.children ?? [] {
            try visit(child, parent: value, ancestors: ancestors.union([id]))
        }
    }
    try visit(mainGroup, parent: "", ancestors: [])
    let targets = objects.filter { $0.value.isa == "PBXNativeTarget" }
    if Set(targets.values.compactMap(\.name)) != Set(ArchitecturePolicy.targetRoots.keys) {
        fail("target set violates the app/widget/test boundary")
    }
    for (id, target) in targets {
        guard let name = target.name, let allowedRoots = ArchitecturePolicy.targetRoots[name] else {
            continue
        }
        var members: Set<String> = []
        var products = Set(target.packageProductDependencies ?? [])
        for phaseID in target.buildPhases ?? [] {
            guard let phase = objects[phaseID] else {
                throw ArchitectureError("Missing build phase \(phaseID)")
            }
            for fileID in phase.files ?? [] {
                guard let file = objects[fileID] else {
                    throw ArchitectureError("Missing build file \(fileID)")
                }
                if let product = file.productRef { products.insert(product) }
                if phase.isa == "PBXSourcesBuildPhase" {
                    guard let ref = file.fileRef, let path = resolvedPaths[ref] else {
                        throw ArchitectureError(
                            "\(projectPath):1: Cannot resolve source membership in \(name)")
                    }
                    members.insert(path)
                }
            }
        }
        var roots: Set<String> = []
        for groupID in target.fileSystemSynchronizedGroups ?? [] {
            guard let group = objects[groupID], let path = resolvedPaths[groupID] else {
                throw ArchitectureError(
                    "\(projectPath):1: Cannot resolve synchronized group in \(name)")
            }
            roots.insert(path)
            var excluded: Set<String> = []
            for exceptionID in group.exceptions ?? [] {
                guard let exception = objects[exceptionID] else {
                    throw ArchitectureError("Missing membership exception \(exceptionID)")
                }
                if exception.target == id {
                    excluded.formUnion(exception.membershipExceptions ?? [])
                }
            }
            members.formUnion(
                paths.filter {
                    $0.hasPrefix(path + "/")
                        && !excluded.contains(String($0.dropFirst(path.count + 1)))
                })
        }
        if roots != allowedRoots {
            fail(
                "\(name) source folders \(roots.sorted()) violate required folders \(allowedRoots.sorted())"
            )
        }
        for path in members where !allowedRoots.contains(where: { path.hasPrefix($0 + "/") }) {
            fail("\(name) source \(path) violates source ownership")
        }
        if name == "ClinicalWidgetExtension" { result.widgetSources = members }
        if name == "ClinicalWidgetExtension", !(target.dependencies ?? []).isEmpty {
            fail("\(name) must not depend on app targets")
        }
        var productNames: Set<String> = []
        for productID in products {
            guard let productName = objects[productID]?.productName else {
                throw ArchitectureError(
                    "\(projectPath):1: Cannot resolve \(name) package product \(productID)")
            }
            productNames.insert(productName)
        }
        if name == "ClinicalWidgetExtension",
            !productNames.intersection(ArchitecturePolicy.widgetForbiddenImports).isEmpty
        {
            fail(
                "\(name) products \(productNames.sorted()) violate the model-only Clinical package boundary"
            )
        }
        let required: Set<String> =
            name == "ClinicalWidgetExtension"
            ? ["ClinicalModels"]
            : name == "clinical-swiftUITests" ? [] : ["ClinicalModels", "ClinicalPersistence"]
        if !required.isSubset(of: productNames) {
            fail("\(name) is missing required package products \(required.sorted())")
        }
    }
    return result
}

func checkArchitecture(root: URL, staged: Bool) throws -> [String] {
    if staged {
        let snapshot = FileManager.default.temporaryDirectory.appending(
            path: "clinical-architecture-\(UUID())")
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: snapshot) }
        _ = try command(
            root, "git", ["checkout-index", "--all", "--prefix=" + snapshot.path + "/"])
        return try checkArchitecture(root: snapshot, staged: false)
    }
    var paths: [String] = []
    for folder in ["Sources", "Tests", "clinical-swift", "ClinicalShared", "ClinicalWidget"] {
        guard let files = FileManager.default.enumerator(atPath: root.appending(path: folder).path)
        else {
            throw ArchitectureError("Missing required source folder \(folder)")
        }
        for case let path as String in files where path.hasSuffix(".swift") {
            paths.append(folder + "/" + path)
        }
    }
    var failures = try checkPackage(packageGraph(root))
    let membership = try checkProject(
        loadXcodeProject(at: root.appending(path: projectPath)), paths: paths)
    failures += membership.failures
    let widgetSources = membership.widgetSources
    for path in paths.sorted() {
        failures += try checkImports(
            path: path, source: String(contentsOf: root.appending(path: path), encoding: .utf8),
            widgetMember: widgetSources.contains(path))
    }
    return failures
}

private func runCLI() {
    do {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.isEmpty || arguments == ["--staged"] else {
            throw ArchitectureError("Usage: check_architecture.sh [--staged]")
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let path = String(
            decoding: try command(cwd, "git", ["rev-parse", "--show-toplevel"]),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let failures = try checkArchitecture(
            root: URL(fileURLWithPath: path), staged: arguments == ["--staged"])
        for failure in failures { print(failure) }
        if !failures.isEmpty { exit(1) }
        print("Architecture checks passed\(arguments.isEmpty ? "" : " for the Git index").")
    } catch {
        FileHandle.standardError.write(Data("Architecture check failed: \(error)\n".utf8))
        exit(1)
    }
}

#if !SCRIPT_TESTS
    let _ = runCLI()
#endif
