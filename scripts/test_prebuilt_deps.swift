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
        "prebuilt-deps-test-\(UUID().uuidString)")
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

    // Xcode upgrade invalidates both deps and project fingerprints.
    let xcodeChanged = try computeFingerprints(repoRoot: tmp, xcodeVersion: "27.3-27C10")
    try expect(
        xcodeChanged.deps != base.deps, "Xcode version change must invalidate deps fingerprint.")
    try expect(
        xcodeChanged.project != base.project,
        "Xcode version change must invalidate project fingerprint.")

    // Editing project.pbxproj alone invalidates project fingerprint without invalidating deps.
    try Data("pbx v2\n".utf8).write(to: pbxURL)
    let pbxChanged = try computeFingerprints(repoRoot: tmp, xcodeVersion: "27.2-27B52")
    try expect(
        pbxChanged.deps == base.deps, "project.pbxproj change must keep deps fingerprint stable.")
    try expect(
        pbxChanged.project != base.project,
        "project.pbxproj change must invalidate project fingerprint.")

    // Editing a file under Sources/ invalidates both deps and project fingerprints.
    try Data("public struct Sample { public var id = 1 }\n".utf8).write(to: sourceFile)
    let sourceChanged = try computeFingerprints(repoRoot: tmp, xcodeVersion: "27.2-27B52")
    try expect(sourceChanged.deps != base.deps, "Sources/ change must invalidate deps fingerprint.")
    try expect(
        sourceChanged.project != pbxChanged.project,
        "Sources/ change must invalidate project fingerprint.")

    // Real project.pbxproj rewrite produces a valid plist with zero SPM packages and 22 XCFrameworks.
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
        "Rewritten pbxproj must drop remote packages.")
    try expect(
        !rewritten.contains("XCLocalSwiftPackageReference"),
        "Rewritten pbxproj must drop local package.")
    try expect(
        !rewritten.contains("XCSwiftPackageProductDependency"),
        "Rewritten pbxproj must drop SPM product deps.")
    try expect(
        rewritten.contains("projectDirPath = \"../..\";"),
        "Rewritten pbxproj must set projectDirPath.")
    try expect(
        rewritten.contains("SQLiteData.xcframework"),
        "Rewritten pbxproj must link SQLiteData.xcframework.")
    try expect(
        rewritten.contains("GRDB_GRDB.bundle in Resources"),
        "Rewritten pbxproj must include GRDB bundle.")
    try expect(
        rewritten.contains(
            "-fmodule-map-file=$(PROJECT_DIR)/build/PrebuiltDeps/GRDBSQLite/module.modulemap"),
        "Rewritten pbxproj must pass GRDBSQLite modulemap."
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

        print("PASS prebuilt_deps: fingerprinting, pbxproj/scheme rewrites, and CLI validation")
    }
}
