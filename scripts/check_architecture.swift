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
            || path == "clinical-swift/backups/BackupSettingsView.swift"
            || path == "clinical-swift/unavailable-times/UnavailableTimeEditorView.swift"
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
        let part = Array(marker.utf8)
        return offset + part.count <= bytes.count
            && bytes[offset..<(offset + part.count)].elementsEqual(part)
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

func jsonObject(_ data: Data) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ArchitectureError("Expected a JSON object")
    }
    return value
}

func packageGraph(_ root: URL) throws -> [String: Any] {
    let snapshot = FileManager.default.temporaryDirectory.appending(
        path: "clinical-package-\(UUID())")
    try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: snapshot) }
    // SwiftPM can rewrite platform-specific pins even when only reading the manifest.
    try FileManager.default.copyItem(
        at: root.appending(path: "Package.swift"), to: snapshot.appending(path: "Package.swift"))
    return try jsonObject(command(snapshot, "swift", ["package", "dump-package"]))
}

func checkPackage(_ graph: [String: Any]) throws -> [String] {
    guard let targets = graph["targets"] as? [[String: Any]],
        let products = graph["products"] as? [[String: Any]]
    else {
        throw ArchitectureError("Package.swift:1: Cannot read package targets and products")
    }
    var failures: [String] = []
    let names = Set(targets.compactMap { $0["name"] as? String })
    if names != Set(ArchitecturePolicy.layers.keys) {
        failures.append(
            "Package.swift:1: target set \(names.sorted()) violates the three-target package boundary"
        )
    }
    for target in targets {
        guard let name = target["name"] as? String, let policy = ArchitecturePolicy.layers[name],
            let dependencies = target["dependencies"] as? [[String: Any]]
        else {
            failures.append(
                "Package.swift:1: unknown or invalid target \(target["name"] ?? "missing name")")
            continue
        }
        let expectedPath = (name == "ClinicalDataTests" ? "Tests/" : "Sources/") + name
        if let path = target["path"] as? String, path != expectedPath {
            failures.append(
                "Package.swift:1: \(name) path \(path) violates standard layout \(expectedPath)")
        }
        if target["sources"] != nil || !(target["exclude"] as? [String] ?? []).isEmpty {
            failures.append("Package.swift:1: \(name) must compile the full standard source folder")
        }
        for dependency in dependencies {
            let key: String
            if let product = dependency["product"] as? [Any], product.count >= 2,
                let name = product[0] as? String, let package = product[1] as? String
            {
                key = package.lowercased() + "/" + name
                if product.count > 2 && !(product[2] is NSNull) {
                    failures.append(
                        "Package.swift:1: module aliases violate the explicit dependency policy")
                }
            } else if let values = (dependency["byName"] ?? dependency["target"]) as? [Any],
                let name = values.first as? String
            {
                key = name
            } else {
                throw ArchitectureError(
                    "Package.swift:1: Cannot read \(name) dependency \(dependency)")
            }
            if !policy.dependencies.contains(key) {
                failures.append(
                    "Package.swift:1: \(name) dependency \(key) violates allowed dependencies \(policy.dependencies.sorted())"
                )
            }
        }
    }
    if Set(products.compactMap { $0["name"] as? String }) != [
        "ClinicalModels", "ClinicalPersistence",
    ] {
        failures.append(
            "Package.swift:1: products must expose only ClinicalModels and ClinicalPersistence")
    }
    for product in products {
        if let name = product["name"] as? String, product["targets"] as? [String] != [name] {
            failures.append("Package.swift:1: product \(name) must expose only its own target")
        }
    }
    return failures
}

let projectPath = "clinical-swift.xcodeproj/project.pbxproj"

struct ProjectMembership {
    var widgetSources: Set<String> = []
    var failures: [String] = []
}

func checkProject(_ project: [String: Any], paths: [String]) throws -> ProjectMembership {
    guard let objects = project["objects"] as? [String: [String: Any]],
        let rootID = project["rootObject"] as? String,
        let mainGroup = objects[rootID]?["mainGroup"] as? String
    else {
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
        let tree = object["sourceTree"] as? String ?? "<group>"
        let path = object["path"] as? String ?? ""
        let value =
            tree == "SOURCE_ROOT"
            ? path : [parent, path].filter { !$0.isEmpty }.joined(separator: "/")
        resolvedPaths[id] = value
        for child in object["children"] as? [String] ?? [] {
            try visit(child, parent: value, ancestors: ancestors.union([id]))
        }
    }
    try visit(mainGroup, parent: "", ancestors: [])
    let targets = objects.filter { $0.value["isa"] as? String == "PBXNativeTarget" }
    if Set(targets.values.compactMap { $0["name"] as? String })
        != Set(ArchitecturePolicy.targetRoots.keys)
    {
        fail("target set violates the app/widget/test boundary")
    }
    for (id, target) in targets {
        guard let name = target["name"] as? String,
            let allowedRoots = ArchitecturePolicy.targetRoots[name]
        else { continue }
        var members: Set<String> = []
        var products = Set(target["packageProductDependencies"] as? [String] ?? [])
        for phaseID in target["buildPhases"] as? [String] ?? [] {
            guard let phase = objects[phaseID] else {
                throw ArchitectureError("Missing build phase \(phaseID)")
            }
            for fileID in phase["files"] as? [String] ?? [] {
                guard let file = objects[fileID] else {
                    throw ArchitectureError("Missing build file \(fileID)")
                }
                if let product = file["productRef"] as? String { products.insert(product) }
                if phase["isa"] as? String == "PBXSourcesBuildPhase" {
                    guard let ref = file["fileRef"] as? String, let path = resolvedPaths[ref] else {
                        throw ArchitectureError(
                            "\(projectPath):1: Cannot resolve source membership in \(name)")
                    }
                    members.insert(path)
                }
            }
        }
        var roots: Set<String> = []
        for groupID in target["fileSystemSynchronizedGroups"] as? [String] ?? [] {
            guard let group = objects[groupID], let path = resolvedPaths[groupID] else {
                throw ArchitectureError(
                    "\(projectPath):1: Cannot resolve synchronized group in \(name)")
            }
            roots.insert(path)
            var excluded: Set<String> = []
            for exceptionID in group["exceptions"] as? [String] ?? [] {
                guard let exception = objects[exceptionID] else {
                    throw ArchitectureError("Missing membership exception \(exceptionID)")
                }
                if exception["target"] as? String == id {
                    excluded.formUnion(exception["membershipExceptions"] as? [String] ?? [])
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
        for path in members {
            if !allowedRoots.contains(where: { path.hasPrefix($0 + "/") }) {
                fail("\(name) source \(path) violates source ownership")
            }
        }
        if name == "ClinicalWidgetExtension" { result.widgetSources = members }
        if name == "ClinicalWidgetExtension", !(target["dependencies"] as? [String] ?? []).isEmpty {
            fail("\(name) must not depend on app targets")
        }
        var productNames: Set<String> = []
        for productID in products {
            guard let product = objects[productID],
                let productName = product["productName"] as? String
            else {
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
    var widgetSources: Set<String> = []
    #if os(macOS)
        let data = try command(root, "plutil", ["-convert", "json", "-o", "-", projectPath])
        let membership = try checkProject(jsonObject(data), paths: paths)
        failures += membership.failures
        widgetSources = membership.widgetSources
    #endif
    for path in paths.sorted() {
        failures += try checkImports(
            path: path, source: String(contentsOf: root.appending(path: path), encoding: .utf8),
            widgetMember: widgetSources.contains(path))
    }
    return failures
}

#if !ARCHITECTURE_TESTS
    @main
    struct CheckArchitecture {
        static func main() {
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
    }
#endif
