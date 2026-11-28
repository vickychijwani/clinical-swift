import Foundation

private struct PrebuiltTestError: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw PrebuiltTestError(description: message)
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
        throw PrebuiltTestError(description: String(decoding: data, as: UTF8.self))
    }
    return data
}

private func runUnitTests(repoRoot: URL) throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent(
        "prebuilt-deps-test-\(UUID().uuidString)"
    )
    defer { try? fm.removeItem(at: tmp) }

    try fm.createDirectory(
        at: tmp.appendingPathComponent("Sources/ClinicalModels"),
        withIntermediateDirectories: true
    )
    try fm.createDirectory(
        at: tmp.appendingPathComponent("clinical-swift.xcodeproj/xcshareddata/xcschemes"),
        withIntermediateDirectories: true
    )

    let packageSwift = tmp.appendingPathComponent("Package.swift")
    let packageResolved = tmp.appendingPathComponent("Package.resolved")
    let sourceFile = tmp.appendingPathComponent("Sources/ClinicalModels/Sample.swift")
    let pbxURL = tmp.appendingPathComponent("clinical-swift.xcodeproj/project.pbxproj")
    let schemeURL = tmp.appendingPathComponent(
        "clinical-swift.xcodeproj/xcshareddata/xcschemes/clinical-swift.xcscheme"
    )

    try Data("// package v1\n".utf8).write(to: packageSwift)
    try Data("{\"pins\":[]}\n".utf8).write(to: packageResolved)
    try Data("public struct Sample {}\n".utf8).write(to: sourceFile)
    try Data("pbx v1\n".utf8).write(to: pbxURL)
    try Data("scheme v1\n".utf8).write(to: schemeURL)

    let base = try computeFingerprints(repoRoot: tmp, xcodeVersion: "27.2-27B52")
    let repeatBase = try computeFingerprints(repoRoot: tmp, xcodeVersion: "27.2-27B52")
    try expect(base == repeatBase, "Fingerprints must be deterministic.")

    // Editing Sources/ must NOT bust either fingerprint because Sources/ compiles natively.
    try Data("public struct Sample { public var id = 1 }\n".utf8).write(to: sourceFile)
    let sourceChanged = try computeFingerprints(repoRoot: tmp, xcodeVersion: "27.2-27B52")
    try expect(sourceChanged == base, "Sources/ edits must keep prebuilt fingerprints stable.")

    // Architecture change invalidates both deps and project fingerprints.
    let archChanged = try computeFingerprints(
        repoRoot: tmp,
        xcodeVersion: "27.2-27B52",
        arch: currentHostArch() == "arm64" ? "x86_64" : "arm64"
    )
    try expect(
        archChanged.deps != base.deps,
        "Host architecture change must invalidate deps fingerprint."
    )

    // Nested warm-up make strips inherited MAKEFLAGS and clears SIMULATOR_NAME / EXTRA_BUILD_FLAGS.
    let cleanEnv = canonicalWarmMakeEnvironment(
        baseEnvironment: [
            "MAKEFLAGS": "SIMULATOR_NAME=task EXTRA_BUILD_FLAGS=FOO=1",
            "MFLAGS": "-w",
            "MAKEOVERRIDES": "SIMULATOR_NAME=task",
            "MAKELEVEL": "1",
            "PATH": "/usr/bin:/bin",
        ],
        developerDir: "/Applications/Xcode.app/Contents/Developer"
    )
    try expect(cleanEnv["MAKEFLAGS"] == nil, "Nested make env must strip MAKEFLAGS.")
    try expect(cleanEnv["MFLAGS"] == nil, "Nested make env must strip MFLAGS.")
    try expect(cleanEnv["MAKEOVERRIDES"] == nil, "Nested make env must strip MAKEOVERRIDES.")
    try expect(cleanEnv["MAKELEVEL"] == nil, "Nested make env must strip MAKELEVEL.")
    try expect(
        cleanEnv["DEVELOPER_DIR"] == "/Applications/Xcode.app/Contents/Developer",
        "Nested make env must preserve DEVELOPER_DIR."
    )

    let dummyReq = PrebuiltEnsureRequest(
        repoRoot: tmp,
        derivedData: tmp.appendingPathComponent("dd"),
        outputDir: tmp.appendingPathComponent("out"),
        simulatorID: "SIM-123",
        developerDir: "/Applications/Xcode.app/Contents/Developer"
    )
    let warmArgs = canonicalWarmMakeArguments(request: dummyReq)
    try expect(warmArgs.contains("SIMULATOR_NAME="), "Nested make must clear SIMULATOR_NAME.")
    try expect(
        warmArgs.contains("EXTRA_BUILD_FLAGS="),
        "Nested make must clear EXTRA_BUILD_FLAGS."
    )

    // Atomic writer creates and replaces existing files cleanly.
    let atomicFile = tmp.appendingPathComponent("nested/stamp.txt")
    try writeAtomically("first\n", to: atomicFile)
    try writeAtomically("second\n", to: atomicFile)
    try expect(
        try String(contentsOf: atomicFile, encoding: .utf8) == "second\n",
        "writeAtomically must replace existing content."
    )

    // Xcode upgrade invalidates both deps and project fingerprints.
    let xcodeChanged = try computeFingerprints(repoRoot: tmp, xcodeVersion: "27.3-27C10")
    try expect(
        xcodeChanged.deps != base.deps,
        "Xcode version change must invalidate deps fingerprint."
    )
    try expect(
        xcodeChanged.project != base.project,
        "Xcode version change must invalidate project fingerprint."
    )

    // Updating Package.resolved invalidates both deps and project fingerprints.
    try Data("{\"pins\":[\"v2\"]}\n".utf8).write(to: packageResolved)
    let pinChanged = try computeFingerprints(repoRoot: tmp, xcodeVersion: "27.2-27B52")
    try expect(
        pinChanged.deps != base.deps,
        "Package.resolved change must invalidate deps fingerprint."
    )
    try expect(
        pinChanged.project != base.project,
        "Package.resolved change must invalidate project fingerprint."
    )

    // Editing project.pbxproj alone invalidates project fingerprint without invalidating deps.
    try Data("pbx v2\n".utf8).write(to: pbxURL)
    let pbxChanged = try computeFingerprints(repoRoot: tmp, xcodeVersion: "27.2-27B52")
    try expect(
        pbxChanged.deps == pinChanged.deps,
        "project.pbxproj change must keep deps fingerprint stable."
    )
    try expect(
        pbxChanged.project != pinChanged.project,
        "project.pbxproj change must invalidate project fingerprint."
    )

    // Real project.pbxproj rewrite produces a valid plist with 0 SPM packages, 20 third-party XCFrameworks, and 2 native Sources targets.
    let realPBX = try String(
        contentsOf: repoRoot.appendingPathComponent("clinical-swift.xcodeproj/project.pbxproj"),
        encoding: .utf8
    )
    let rewritten = try rewriteProjectForPrebuilt(
        canonicalPBXProj: realPBX,
        outputRelativePath: "build/PrebuiltDeps",
        projectDirPath: "../..",
        resourceBundles: PrebuiltModules.resourceBundles
    )
    try expect(
        !rewritten.contains("XCRemoteSwiftPackageReference"),
        "Rewritten pbxproj must drop remote packages."
    )
    try expect(
        !rewritten.contains("XCLocalSwiftPackageReference"),
        "Rewritten pbxproj must drop local package."
    )
    try expect(
        !rewritten.contains("XCSwiftPackageProductDependency"),
        "Rewritten pbxproj must drop SPM product deps."
    )
    try expect(
        !rewritten.contains("ClinicalModels.xcframework"),
        "ClinicalModels must compile natively, not as an XCFramework."
    )
    try expect(
        !rewritten.contains("ClinicalPersistence.xcframework"),
        "ClinicalPersistence must compile natively, not as an XCFramework."
    )
    try expect(
        rewritten.contains("path = Sources/ClinicalModels;"),
        "Rewritten pbxproj must mount Sources/ClinicalModels."
    )
    try expect(
        rewritten.contains("path = Sources/ClinicalPersistence;"),
        "Rewritten pbxproj must mount Sources/ClinicalPersistence."
    )
    try expect(
        rewritten.contains("libClinicalModels.a in Frameworks"),
        "Rewritten pbxproj must link libClinicalModels.a."
    )
    try expect(
        rewritten.contains("libClinicalPersistence.a in Frameworks"),
        "Rewritten pbxproj must link libClinicalPersistence.a."
    )
    try expect(
        rewritten.contains("Macros/StructuredQueriesSQLiteMacros#StructuredQueriesSQLiteMacros"),
        "Rewritten pbxproj must pass prebuilt macro plugins to ClinicalPersistence."
    )
    try expect(
        rewritten.contains("SQLiteData.xcframework"),
        "Rewritten pbxproj must link third-party SQLiteData.xcframework."
    )
    try expect(
        rewritten.contains("GRDB_GRDB.bundle in Resources"),
        "Rewritten pbxproj must include GRDB bundle."
    )

    let lintTarget = tmp.appendingPathComponent("rewritten.pbxproj")
    try Data(rewritten.utf8).write(to: lintTarget)
    try runCommand(["plutil", "-lint", lintTarget.path])

    // Scheme rewrite updates container references to the generated project relative to projectDirPath.
    let realScheme = try String(
        contentsOf: repoRoot.appendingPathComponent(
            "clinical-swift.xcodeproj/xcshareddata/xcschemes/clinical-swift.xcscheme"
        ),
        encoding: .utf8
    )
    let rewrittenScheme = rewriteSchemeForPrebuilt(
        realScheme,
        prebuiltProjectRelativePath: "build/PrebuiltDeps/clinical-swift-prebuilt.xcodeproj"
    )
    try expect(
        !rewrittenScheme.contains("container:clinical-swift.xcodeproj"),
        "Rewritten scheme must not point to canonical project."
    )
    try expect(
        rewrittenScheme.contains("container:build/PrebuiltDeps/clinical-swift-prebuilt.xcodeproj"),
        "Rewritten scheme must point to prebuilt project."
    )
}

@main
struct PrebuiltDepsTests {
    static func main() throws {
        let repoRoot = URL(fileURLWithPath: CommandLine.arguments[1])
        try runUnitTests(repoRoot: repoRoot)

        // Verify the real CLI compiles and rejects missing arguments cleanly.
        let cli = ProcessInfo.processInfo.environment["SCRIPT_CLI_BIN"]!
        do {
            try runCommand([cli])
            throw PrebuiltTestError(description: "CLI accepted missing arguments.")
        } catch let error as PrebuiltTestError {
            try expect(error.description.contains("Usage:"), error.description)
        }

        print(
            "PASS prebuilt_deps: fingerprinting, 4-target pbxproj/scheme rewrites, and CLI validation"
        )
    }
}
