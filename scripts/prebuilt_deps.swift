import CryptoKit
import Foundation

struct PrebuiltDepsError: Error, CustomStringConvertible {
    let description: String
}

enum PrebuiltModules {
    static let schemaVersion = "v1"

    static let all: [String] = [
        "ClinicalModels",
        "ClinicalPersistence",
        "Clocks",
        "CombineSchedulers",
        "ConcurrencyExtras",
        "CustomDump",
        "Dependencies",
        "GRDB",
        "IdentifiedCollections",
        "InternalCollectionsUtilities",
        "IssueReporting",
        "OrderedCollections",
        "Perception",
        "PerceptionCore",
        "SQLiteData",
        "Sharing",
        "Sharing1",
        "Sharing2",
        "StructuredQueries",
        "StructuredQueriesCore",
        "StructuredQueriesSQLite",
        "StructuredQueriesSQLiteCore",
    ]

    static let widget: Set<String> = [
        "ClinicalModels",
        "Clocks",
        "CombineSchedulers",
        "ConcurrencyExtras",
        "CustomDump",
        "Dependencies",
        "GRDB",
        "IssueReporting",
        "PerceptionCore",
    ]

    static let resourceBundles: [String] = [
        "GRDB_GRDB.bundle",
        "swift-sharing_Sharing.bundle",
    ]
}

struct PrebuiltFingerprints: Equatable {
    let deps: String
    let project: String
}

struct PrebuiltEnsureRequest {
    let repoRoot: URL
    let derivedData: URL
    let outputDir: URL
    let simulatorID: String
    let developerDir: String
}

private func hexDigest(_ hasher: SHA256) -> String {
    hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private func hashFileIfPresent(at url: URL, label: String, into hasher: inout SHA256) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    hasher.update(data: Data("FILE:\(label)\n".utf8))
    hasher.update(data: try Data(contentsOf: url))
    hasher.update(data: Data([0]))
}

func readXcodeVersion(developerDir: String) -> String? {
    let versionPlist = URL(fileURLWithPath: developerDir)
        .deletingLastPathComponent()
        .appendingPathComponent("version.plist")
    guard
        let data = try? Data(contentsOf: versionPlist),
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: Any]
    else {
        return nil
    }
    let shortVersion = plist["CFBundleShortVersionString"] as? String ?? ""
    let buildVersion = plist["ProductBuildVersion"] as? String ?? ""
    guard !shortVersion.isEmpty || !buildVersion.isEmpty else { return nil }
    return "\(shortVersion)-\(buildVersion)"
}

func computeFingerprints(repoRoot: URL, xcodeVersion: String) throws -> PrebuiltFingerprints {
    let fm = FileManager.default
    var depsHasher = SHA256()
    depsHasher.update(data: Data("SCHEMA:\(PrebuiltModules.schemaVersion)\n".utf8))
    depsHasher.update(data: Data("XCODE:\(xcodeVersion)\n".utf8))
    depsHasher.update(data: Data("MODULES:\(PrebuiltModules.all.joined(separator: ","))\n".utf8))

    try hashFileIfPresent(
        at: repoRoot.appendingPathComponent("Package.swift"),
        label: "Package.swift",
        into: &depsHasher
    )
    try hashFileIfPresent(
        at: repoRoot.appendingPathComponent("Package.resolved"),
        label: "Package.resolved",
        into: &depsHasher
    )
    try hashFileIfPresent(
        at: repoRoot.appendingPathComponent(
            "clinical-swift.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        ),
        label: "xcodeproj/Package.resolved",
        into: &depsHasher
    )

    let sourcesDir = repoRoot.appendingPathComponent("Sources")
    if fm.fileExists(atPath: sourcesDir.path),
        let enumerator = fm.enumerator(
            at: sourcesDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
    {
        var sourceFiles: [(relativePath: String, url: URL)] = []
        let basePath = sourcesDir.standardizedFileURL.path + "/"
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let fullPath = fileURL.standardizedFileURL.path
            let rel =
                fullPath.hasPrefix(basePath)
                ? String(fullPath.dropFirst(basePath.count)) : fileURL.lastPathComponent
            sourceFiles.append((rel, fileURL))
        }
        sourceFiles.sort { $0.relativePath < $1.relativePath }
        for item in sourceFiles {
            try hashFileIfPresent(
                at: item.url,
                label: "Sources/\(item.relativePath)",
                into: &depsHasher
            )
        }
    }

    let depsHash = hexDigest(depsHasher)

    var projectHasher = SHA256()
    projectHasher.update(data: Data("DEPS:\(depsHash)\n".utf8))
    try hashFileIfPresent(
        at: repoRoot.appendingPathComponent("clinical-swift.xcodeproj/project.pbxproj"),
        label: "project.pbxproj",
        into: &projectHasher
    )
    try hashFileIfPresent(
        at: repoRoot.appendingPathComponent(
            "clinical-swift.xcodeproj/xcshareddata/xcschemes/clinical-swift.xcscheme"
        ),
        label: "clinical-swift.xcscheme",
        into: &projectHasher
    )

    return PrebuiltFingerprints(deps: depsHash, project: hexDigest(projectHasher))
}

private func makeObjectID(_ prefix: String, index: Int) -> String {
    String(format: "F0%@%018X", prefix, index)
}

private func regexReplace(
    in text: String,
    pattern: String,
    template: String,
    dotMatchesLineSeparators: Bool = false
) throws -> (result: String, count: Int) {
    var options: NSRegularExpression.Options = []
    if dotMatchesLineSeparators {
        options.insert(.dotMatchesLineSeparators)
    }
    let regex = try NSRegularExpression(pattern: pattern, options: options)
    let range = NSRange(text.startIndex..., in: text)
    let matches = regex.numberOfMatches(in: text, range: range)
    let result = regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    return (result, matches)
}

func rewriteProjectForPrebuilt(
    canonicalPBXProj: String,
    outputRelativePath: String,
    projectDirPath: String,
    resourceBundles: [String]
) throws -> String {
    var text = canonicalPBXProj

    for section in [
        "XCLocalSwiftPackageReference",
        "XCRemoteSwiftPackageReference",
        "XCSwiftPackageProductDependency",
    ] {
        text =
            try regexReplace(
                in: text,
                pattern: #"\n/\* Begin "# + section + #" section \*/.*?/\* End "# + section
                    + #" section \*/\n"#,
                template: "\n",
                dotMatchesLineSeparators: true
            ).result
    }

    text =
        try regexReplace(
            in: text,
            pattern: #"\t\t\tpackageReferences = \(\n.*?\t\t\t\);\n"#,
            template: "",
            dotMatchesLineSeparators: true
        ).result

    text =
        try regexReplace(
            in: text,
            pattern: #"\t\t\tpackageProductDependencies = \(\n.*?\t\t\t\);\n"#,
            template: "\t\t\tpackageProductDependencies = (\n\t\t\t);\n",
            dotMatchesLineSeparators: true
        ).result

    text =
        try regexReplace(
            in: text,
            pattern:
                #"\t\t[0-9A-F]+ /\* .* in Frameworks \*/ = \{isa = PBXBuildFile; (?:productRef = .*?; )?\};\n"#,
            template: ""
        ).result

    // Point the generated project back to the repository root so relative source/plist paths resolve.
    let projectDirReplacement = try regexReplace(
        in: text,
        pattern: #"\t\t\tprojectDirPath = "";\n\t\t\tprojectRoot = "";\n"#,
        template:
            "\t\t\tprojectDirPath = \"\(projectDirPath)\";\n\t\t\tprojectRoot = \"\(projectDirPath)\";\n"
    )
    guard projectDirReplacement.count == 1 else {
        throw PrebuiltDepsError(
            description: "Could not locate projectDirPath/projectRoot in project.pbxproj.")
    }
    text = projectDirReplacement.result

    var fileRefs: [String] = []
    var buildFiles: [String] = []
    var appFrameworkEntries: [String] = []
    var widgetFrameworkEntries: [String] = []
    var appResourceEntries: [String] = []

    for (offset, mod) in PrebuiltModules.all.enumerated() {
        let idx = offset + 1
        let fref = makeObjectID("0100", index: idx)
        let appBuild = makeObjectID("0200", index: idx)
        fileRefs.append(
            "\t\t\(fref) /* \(mod).xcframework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; name = \(mod).xcframework; path = \(outputRelativePath)/XCFrameworks/\(mod).xcframework; sourceTree = SOURCE_ROOT; };"
        )
        buildFiles.append(
            "\t\t\(appBuild) /* \(mod).xcframework in Frameworks */ = {isa = PBXBuildFile; fileRef = \(fref) /* \(mod).xcframework */; };"
        )
        appFrameworkEntries.append("\t\t\t\t\(appBuild) /* \(mod).xcframework in Frameworks */,")

        if PrebuiltModules.widget.contains(mod) {
            let widgetBuild = makeObjectID("0300", index: idx)
            buildFiles.append(
                "\t\t\(widgetBuild) /* \(mod).xcframework in Frameworks */ = {isa = PBXBuildFile; fileRef = \(fref) /* \(mod).xcframework */; };"
            )
            widgetFrameworkEntries.append(
                "\t\t\t\t\(widgetBuild) /* \(mod).xcframework in Frameworks */,")
        }
    }

    for (offset, bundle) in resourceBundles.enumerated() {
        let idx = offset + 1
        let fref = makeObjectID("0400", index: idx)
        let resBuild = makeObjectID("0500", index: idx)
        fileRefs.append(
            "\t\t\(fref) /* \(bundle) */ = {isa = PBXFileReference; lastKnownFileType = wrapper.cfbundle; name = \(bundle); path = \(outputRelativePath)/Resources/\(bundle); sourceTree = SOURCE_ROOT; };"
        )
        buildFiles.append(
            "\t\t\(resBuild) /* \(bundle) in Resources */ = {isa = PBXBuildFile; fileRef = \(fref) /* \(bundle) */; };"
        )
        appResourceEntries.append("\t\t\t\t\(resBuild) /* \(bundle) in Resources */,")
    }

    let buildFileMarker = "/* Begin PBXBuildFile section */\n"
    guard let buildFileRange = text.range(of: buildFileMarker) else {
        throw PrebuiltDepsError(description: "Missing PBXBuildFile section in project.pbxproj.")
    }
    text.replaceSubrange(
        buildFileRange,
        with: buildFileMarker + buildFiles.joined(separator: "\n") + "\n"
    )

    let fileRefMarker = "/* Begin PBXFileReference section */\n"
    guard let fileRefRange = text.range(of: fileRefMarker) else {
        throw PrebuiltDepsError(description: "Missing PBXFileReference section in project.pbxproj.")
    }
    text.replaceSubrange(
        fileRefRange,
        with: fileRefMarker + fileRefs.joined(separator: "\n") + "\n"
    )

    func replaceBuildPhase(
        phaseID: String,
        comment: String,
        isa: String,
        entries: [String]
    ) throws {
        let pattern =
            #"(\t\t"# + phaseID + #" /\* "# + comment + #" \*/ = \{\n\t\t\tisa = "# + isa
            + #";\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = \(\n).*?(\t\t\t\);\n)"#
        let joined = entries.isEmpty ? "" : entries.joined(separator: "\n") + "\n"
        let replaced = try regexReplace(
            in: text,
            pattern: pattern,
            template: "$1" + NSRegularExpression.escapedTemplate(for: joined) + "$2",
            dotMatchesLineSeparators: true
        )
        guard replaced.count == 1 else {
            throw PrebuiltDepsError(description: "Could not patch \(isa) \(phaseID).")
        }
        text = replaced.result
    }

    try replaceBuildPhase(
        phaseID: "79438C402FD2D07100C0E6EF",
        comment: "Frameworks",
        isa: "PBXFrameworksBuildPhase",
        entries: appFrameworkEntries
    )
    try replaceBuildPhase(
        phaseID: "B20000000000000000000006",
        comment: "Frameworks",
        isa: "PBXFrameworksBuildPhase",
        entries: widgetFrameworkEntries
    )
    try replaceBuildPhase(
        phaseID: "8BE2A0132FE0000000000005",
        comment: "Frameworks",
        isa: "PBXFrameworksBuildPhase",
        entries: []
    )
    try replaceBuildPhase(
        phaseID: "D30000000000000000000003",
        comment: "Frameworks",
        isa: "PBXFrameworksBuildPhase",
        entries: []
    )
    if !appResourceEntries.isEmpty {
        try replaceBuildPhase(
            phaseID: "79438C412FD2D07100C0E6EF",
            comment: "Resources",
            isa: "PBXResourcesBuildPhase",
            entries: appResourceEntries
        )
    }

    let extraSettings = """
        				OTHER_LDFLAGS = (
        					"$(inherited)",
        					"-lsqlite3",
        					"-lz",
        				);
        				OTHER_SWIFT_FLAGS = (
        					"$(inherited)",
        					"-Xcc",
        					"-fmodule-map-file=$(PROJECT_DIR)/\(outputRelativePath)/GRDBSQLite/module.modulemap",
        				);

        """
    let escapedExtra = NSRegularExpression.escapedTemplate(for: extraSettings)
    for cfgID in ["79438C512FD2D07300C0E6EF", "B20000000000000000000009"] {
        let pattern =
            #"(\t\t"# + cfgID
            + #" /\* Debug \*/ = \{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = \{\n)"#
        let replaced = try regexReplace(
            in: text,
            pattern: pattern,
            template: "$1" + escapedExtra
        )
        guard replaced.count == 1 else {
            throw PrebuiltDepsError(description: "Could not patch Debug configuration \(cfgID).")
        }
        text = replaced.result
    }

    return text
}

func rewriteSchemeForPrebuilt(_ canonicalScheme: String, prebuiltProjectRelativePath: String)
    -> String
{
    // Xcode resolves container: paths relative to projectDirPath (the repo root).
    canonicalScheme.replacingOccurrences(
        of: "container:clinical-swift.xcodeproj",
        with: "container:\(prebuiltProjectRelativePath)"
    )
}

private func runProcess(
    executable: String,
    arguments: [String],
    currentDirectory: URL? = nil,
    environment: [String: String]? = nil,
    captureOutput: Bool = true
) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    if let environment {
        process.environment = environment
    }
    process.standardInput = FileHandle.nullDevice

    if captureOutput {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errText = String(decoding: errData, as: UTF8.self).trimmingCharacters(
                in: .whitespacesAndNewlines)
            let outText = String(decoding: outData, as: UTF8.self).trimmingCharacters(
                in: .whitespacesAndNewlines)
            let detail = errText.isEmpty ? outText : errText
            throw PrebuiltDepsError(
                description: "\(executable) \(arguments.joined(separator: " ")) failed: \(detail)"
            )
        }
        return String(decoding: outData, as: UTF8.self)
    } else {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PrebuiltDepsError(
                description:
                    "\(executable) \(arguments.joined(separator: " ")) exited with status \(process.terminationStatus)."
            )
        }
        return ""
    }
}

private func frameworkInfoPlist(moduleName: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key>
      <string>en</string>
      <key>CFBundleExecutable</key>
      <string>\(moduleName)</string>
      <key>CFBundleIdentifier</key>
      <string>in.bitehaus.prebuilt.\(moduleName)</string>
      <key>CFBundleInfoDictionaryVersion</key>
      <string>6.0</string>
      <key>CFBundleName</key>
      <string>\(moduleName)</string>
      <key>CFBundlePackageType</key>
      <string>FMWK</string>
      <key>CFBundleShortVersionString</key>
      <string>1.0</string>
      <key>CFBundleVersion</key>
      <string>1</string>
      <key>MinimumOSVersion</key>
      <string>27.0</string>
      <key>CFBundleSupportedPlatforms</key>
      <array>
        <string>iPhoneSimulator</string>
      </array>
    </dict>
    </plist>
    """
}

private func writeAtomically(_ text: String, to url: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let tmp = url.appendingPathExtension("tmp.\(ProcessInfo.processInfo.processIdentifier)")
    try Data(text.utf8).write(to: tmp)
    if fm.fileExists(atPath: url.path) {
        try fm.removeItem(at: url)
    }
    try fm.moveItem(at: tmp, to: url)
}

private func isDepsCacheValid(outputDir: URL, expectedFingerprint: String) -> Bool {
    let fm = FileManager.default
    let stampURL = outputDir.appendingPathComponent("deps.fingerprint")
    guard
        let current = try? String(contentsOf: stampURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
        current == expectedFingerprint
    else {
        return false
    }
    let moduleMap = outputDir.appendingPathComponent("GRDBSQLite/module.modulemap")
    let shimHeader = outputDir.appendingPathComponent("GRDBSQLite/shim.h")
    guard fm.fileExists(atPath: moduleMap.path), fm.fileExists(atPath: shimHeader.path) else {
        return false
    }
    for mod in PrebuiltModules.all {
        let plist = outputDir.appendingPathComponent("XCFrameworks/\(mod).xcframework/Info.plist")
        if !fm.fileExists(atPath: plist.path) {
            return false
        }
    }
    return true
}

private func isProjectCacheValid(outputDir: URL, expectedFingerprint: String) -> Bool {
    let fm = FileManager.default
    let stampURL = outputDir.appendingPathComponent("project.fingerprint")
    guard
        let current = try? String(contentsOf: stampURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
        current == expectedFingerprint
    else {
        return false
    }
    let pbx = outputDir.appendingPathComponent("clinical-swift-prebuilt.xcodeproj/project.pbxproj")
    let scheme = outputDir.appendingPathComponent(
        "clinical-swift-prebuilt.xcodeproj/xcshareddata/xcschemes/clinical-swift.xcscheme"
    )
    return fm.fileExists(atPath: pbx.path) && fm.fileExists(atPath: scheme.path)
}

private func relativePath(from base: URL, to target: URL) -> String {
    let baseComponents = base.standardizedFileURL.pathComponents
    let targetComponents = target.standardizedFileURL.pathComponents
    var common = 0
    while common < min(baseComponents.count, targetComponents.count)
        && baseComponents[common] == targetComponents[common]
    {
        common += 1
    }
    let up = Array(repeating: "..", count: baseComponents.count - common)
    let down = Array(targetComponents.dropFirst(common))
    let combined = up + down
    return combined.isEmpty ? "." : combined.joined(separator: "/")
}

private func rebuildDepsCache(request: PrebuiltEnsureRequest, depsFingerprint: String) throws {
    let fm = FileManager.default
    var env = ProcessInfo.processInfo.environment
    env["DEVELOPER_DIR"] = request.developerDir

    FileHandle.standardError.write(
        Data("[prebuilt] Refreshing canonical Debug simulator dependencies...\n".utf8)
    )
    _ = try runProcess(
        executable: "/usr/bin/make",
        arguments: [
            "--no-print-directory",
            "build",
            "PREBUILT=0",
            "CONFIGURATION=Debug",
            "SIMULATOR_ID=\(request.simulatorID)",
            "XCODE_DEVELOPER_DIR=\(request.developerDir)",
            "DERIVED_DATA=\(request.derivedData.path)",
        ],
        currentDirectory: request.repoRoot,
        environment: env,
        captureOutput: false
    )

    let productsDir = request.derivedData.appendingPathComponent(
        "Build/Products/Debug-iphonesimulator"
    )
    let grdbSQLiteSource = request.repoRoot.appendingPathComponent(
        "build/SourcePackages/checkouts/GRDB.swift/Sources/GRDBSQLite"
    )
    guard fm.fileExists(atPath: grdbSQLiteSource.path) else {
        throw PrebuiltDepsError(
            description: "Missing GRDBSQLite checkout at \(grdbSQLiteSource.path)."
        )
    }

    let pid = ProcessInfo.processInfo.processIdentifier
    let stagingDir = request.outputDir.appendingPathComponent("staging.\(pid)")
    let xcfwTmpDir = request.outputDir.appendingPathComponent("XCFrameworks.tmp.\(pid)")
    let xcfwFinalDir = request.outputDir.appendingPathComponent("XCFrameworks")
    let grdbDestDir = request.outputDir.appendingPathComponent("GRDBSQLite")
    let resourcesDestDir = request.outputDir.appendingPathComponent("Resources")

    defer {
        try? fm.removeItem(at: stagingDir)
        try? fm.removeItem(at: xcfwTmpDir)
    }

    try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: xcfwTmpDir, withIntermediateDirectories: true)

    FileHandle.standardError.write(
        Data("[prebuilt] Packaging \(PrebuiltModules.all.count) binary XCFrameworks...\n".utf8)
    )

    let lock = NSLock()
    var firstError: Error?

    DispatchQueue.concurrentPerform(iterations: PrebuiltModules.all.count) { idx in
        lock.lock()
        let alreadyFailed = firstError != nil
        lock.unlock()
        if alreadyFailed { return }

        let mod = PrebuiltModules.all[idx]
        do {
            let objectFile = productsDir.appendingPathComponent("\(mod).o")
            let swiftModule = productsDir.appendingPathComponent("\(mod).swiftmodule")
            guard fm.fileExists(atPath: objectFile.path), fm.fileExists(atPath: swiftModule.path)
            else {
                throw PrebuiltDepsError(
                    description:
                        "Missing compiled module artifacts for \(mod) in \(productsDir.path)."
                )
            }

            let fwDir = stagingDir.appendingPathComponent("\(mod).framework")
            let modulesDir = fwDir.appendingPathComponent("Modules")
            try fm.createDirectory(at: modulesDir, withIntermediateDirectories: true)

            _ = try runProcess(
                executable: "/usr/bin/xcrun",
                arguments: [
                    "libtool", "-static",
                    "-o", fwDir.appendingPathComponent(mod).path,
                    objectFile.path,
                ],
                environment: env
            )
            try fm.copyItem(
                at: swiftModule, to: modulesDir.appendingPathComponent("\(mod).swiftmodule"))
            try Data(frameworkInfoPlist(moduleName: mod).utf8).write(
                to: fwDir.appendingPathComponent("Info.plist")
            )

            _ = try runProcess(
                executable: "/usr/bin/xcrun",
                arguments: [
                    "xcodebuild", "-create-xcframework",
                    "-allow-internal-distribution",
                    "-framework", fwDir.path,
                    "-output", xcfwTmpDir.appendingPathComponent("\(mod).xcframework").path,
                ],
                environment: env
            )
        } catch {
            lock.lock()
            if firstError == nil {
                firstError = error
            }
            lock.unlock()
        }
    }

    if let firstError {
        throw firstError
    }

    if fm.fileExists(atPath: xcfwFinalDir.path) {
        try fm.removeItem(at: xcfwFinalDir)
    }
    try fm.moveItem(at: xcfwTmpDir, to: xcfwFinalDir)

    if fm.fileExists(atPath: grdbDestDir.path) {
        try fm.removeItem(at: grdbDestDir)
    }
    try fm.copyItem(at: grdbSQLiteSource, to: grdbDestDir)

    if fm.fileExists(atPath: resourcesDestDir.path) {
        try fm.removeItem(at: resourcesDestDir)
    }
    try fm.createDirectory(at: resourcesDestDir, withIntermediateDirectories: true)
    for bundle in PrebuiltModules.resourceBundles {
        let src = productsDir.appendingPathComponent(bundle)
        if fm.fileExists(atPath: src.path) {
            try fm.copyItem(at: src, to: resourcesDestDir.appendingPathComponent(bundle))
        }
    }

    try writeAtomically(
        depsFingerprint + "\n", to: request.outputDir.appendingPathComponent("deps.fingerprint"))
}

private func regeneratePrebuiltProject(request: PrebuiltEnsureRequest, projectFingerprint: String)
    throws
{
    let fm = FileManager.default
    let canonicalPBXURL = request.repoRoot.appendingPathComponent(
        "clinical-swift.xcodeproj/project.pbxproj")
    let canonicalSchemeURL = request.repoRoot.appendingPathComponent(
        "clinical-swift.xcodeproj/xcshareddata/xcschemes/clinical-swift.xcscheme"
    )
    let canonicalPBX = try String(contentsOf: canonicalPBXURL, encoding: .utf8)
    let canonicalScheme = try String(contentsOf: canonicalSchemeURL, encoding: .utf8)

    let outputRel = relativePath(from: request.repoRoot, to: request.outputDir)
    let projectDirPath = relativePath(from: request.outputDir, to: request.repoRoot)
    let resourcesDir = request.outputDir.appendingPathComponent("Resources")
    let presentBundles = PrebuiltModules.resourceBundles.filter {
        fm.fileExists(atPath: resourcesDir.appendingPathComponent($0).path)
    }

    let rewrittenPBX = try rewriteProjectForPrebuilt(
        canonicalPBXProj: canonicalPBX,
        outputRelativePath: outputRel,
        projectDirPath: projectDirPath,
        resourceBundles: presentBundles
    )
    let rewrittenScheme = rewriteSchemeForPrebuilt(
        canonicalScheme,
        prebuiltProjectRelativePath: "\(outputRel)/clinical-swift-prebuilt.xcodeproj"
    )

    let prebuiltProjectURL = request.outputDir.appendingPathComponent(
        "clinical-swift-prebuilt.xcodeproj")
    try writeAtomically(
        rewrittenPBX, to: prebuiltProjectURL.appendingPathComponent("project.pbxproj"))
    try writeAtomically(
        rewrittenScheme,
        to: prebuiltProjectURL.appendingPathComponent(
            "xcshareddata/xcschemes/clinical-swift.xcscheme")
    )
    try writeAtomically(
        projectFingerprint + "\n",
        to: request.outputDir.appendingPathComponent("project.fingerprint")
    )
}

private func ensurePrebuilt(_ request: PrebuiltEnsureRequest) throws {
    let xcodeVersion: String
    if let plistVersion = readXcodeVersion(developerDir: request.developerDir) {
        xcodeVersion = plistVersion
    } else {
        var env = ProcessInfo.processInfo.environment
        env["DEVELOPER_DIR"] = request.developerDir
        xcodeVersion = try runProcess(
            executable: "/usr/bin/xcrun",
            arguments: ["xcodebuild", "-version"],
            environment: env
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let fingerprints = try computeFingerprints(
        repoRoot: request.repoRoot, xcodeVersion: xcodeVersion)
    let depsValid = isDepsCacheValid(
        outputDir: request.outputDir, expectedFingerprint: fingerprints.deps)
    if !depsValid {
        try rebuildDepsCache(request: request, depsFingerprint: fingerprints.deps)
    }

    let projectValid =
        depsValid
        && isProjectCacheValid(
            outputDir: request.outputDir, expectedFingerprint: fingerprints.project)
    if !projectValid {
        try regeneratePrebuiltProject(request: request, projectFingerprint: fingerprints.project)
    }
}

private func parseEnsureArguments(_ arguments: [String]) throws -> PrebuiltEnsureRequest {
    guard arguments.count >= 2, arguments[1] == "ensure" else {
        throw PrebuiltDepsError(
            description:
                "Usage: prebuilt_deps.swift ensure --repo-root PATH --derived-data PATH --output-dir PATH --simulator-id UDID [--developer-dir PATH]"
        )
    }
    var repoRoot = ""
    var derivedData = ""
    var outputDir = ""
    var simulatorID = ""
    var developerDir =
        ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
        ?? "/Applications/Xcode.app/Contents/Developer"

    var index = 2
    while index < arguments.count {
        let flag = arguments[index]
        guard index + 1 < arguments.count else {
            throw PrebuiltDepsError(description: "Missing value for \(flag).")
        }
        let value = arguments[index + 1]
        switch flag {
        case "--repo-root": repoRoot = value
        case "--derived-data": derivedData = value
        case "--output-dir": outputDir = value
        case "--simulator-id": simulatorID = value
        case "--developer-dir": developerDir = value
        default:
            throw PrebuiltDepsError(description: "Unknown option: \(flag).")
        }
        index += 2
    }

    guard !repoRoot.isEmpty, !derivedData.isEmpty, !outputDir.isEmpty, !simulatorID.isEmpty else {
        throw PrebuiltDepsError(
            description:
                "Required options: --repo-root, --derived-data, --output-dir, --simulator-id."
        )
    }

    return PrebuiltEnsureRequest(
        repoRoot: URL(fileURLWithPath: repoRoot),
        derivedData: URL(fileURLWithPath: derivedData),
        outputDir: URL(fileURLWithPath: outputDir),
        simulatorID: simulatorID,
        developerDir: developerDir
    )
}

private func runCLI() {
    do {
        let request = try parseEnsureArguments(CommandLine.arguments)
        try ensurePrebuilt(request)
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}

#if !SCRIPT_TESTS
    let _ = runCLI()
#endif
