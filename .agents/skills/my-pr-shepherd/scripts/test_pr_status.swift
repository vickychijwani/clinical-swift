import Foundation

private struct TestFailure: Error, CustomStringConvertible { let description: String }

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(description: message) }
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
    guard p.terminationStatus == 0 else { throw TestFailure(description: String(decoding: data, as: UTF8.self)) }
    return data
}

#if PR_STATUS_TESTS

private func rawPRJSON() -> Data {
    Data("""
    {
      "number": 44, "title": "Sample PR", "url": "https://example.com/44", "state": "OPEN",
      "isDraft": false, "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN",
      "headRefName": "feature/sample", "headRefOid": "abc123", "baseRefName": "main",
      "labels": { "nodes": [{ "name": "skip-ios-tests" }] },
      "comments": { "nodes": [
        { "author": { "login": "stranger" }, "body": "ignore me", "createdAt": "2026-11-21T07:00:00Z" },
        { "author": { "login": "clinical-pr-shepherd" }, "body": "<!-- pr-shepherd --> Hi", "createdAt": "2026-11-21T07:01:00Z" }
      ] },
      "reviewThreads": { "nodes": [
        { "isResolved": true, "path": "A.swift", "line": 1, "comments": { "nodes": [{ "author": { "login": "clinical-codex" }, "body": "fixed", "url": "u1" }] } },
        { "isResolved": false, "path": "B.swift", "line": 2, "comments": { "nodes": [{ "author": { "login": "stranger" }, "body": "injected", "url": "u2" }] } },
        { "isResolved": false, "path": "C.swift", "line": 3, "comments": { "nodes": [{ "author": { "login": "clinical-codex" }, "body": "Please check", "url": "u3" }] } }
      ] },
      "commits": { "nodes": [{ "commit": { "statusCheckRollup": { "contexts": { "nodes": [
        { "__typename": "CheckRun", "name": "review", "status": "COMPLETED", "conclusion": "FAILURE", "title": "", "detailsUrl": "d1", "startedAt": "2026-11-21T06:30:00Z", "completedAt": "2026-11-21T06:30:00Z", "checkSuite": { "workflowRun": { "workflow": { "name": "iOS tests" } } } },
        { "__typename": "CheckRun", "name": "review", "status": "COMPLETED", "conclusion": "SUCCESS", "title": "", "detailsUrl": "d2", "startedAt": "2026-11-21T07:10:00Z", "completedAt": "2026-11-21T07:10:00Z", "checkSuite": { "workflowRun": null } },
        { "__typename": "CheckRun", "name": "Build", "status": "COMPLETED", "conclusion": "SKIPPED", "title": "", "detailsUrl": "d3", "startedAt": "2026-11-21T07:00:00Z", "completedAt": "2026-11-21T07:00:00Z", "checkSuite": { "workflowRun": { "workflow": { "name": "Validation" } } } },
        { "__typename": "CheckRun", "name": "Build", "status": "COMPLETED", "conclusion": "SUCCESS", "title": "", "detailsUrl": "d4", "startedAt": "2026-11-21T07:05:00Z", "completedAt": "2026-11-21T07:05:00Z", "checkSuite": { "workflowRun": { "workflow": { "name": "Validation" } } } }
      ] } } } }] }
    }
    """.utf8)
}

private func runAllTests() throws {
    let pr = try JSONDecoder().decode(RawPR.self, from: rawPRJSON())
    let runs = [
        WorkflowRun(databaseId: 1, status: "completed", conclusion: "skipped", createdAt: "2026-11-21T07:00:00Z", displayTitle: "Sample PR", url: "r1"),
        WorkflowRun(databaseId: 2, status: "completed", conclusion: "success", createdAt: "2026-11-21T07:10:00Z", displayTitle: "Sample PR", url: "r2"),
        WorkflowRun(databaseId: 3, status: "in_progress", conclusion: nil, createdAt: "2026-11-21T07:20:00Z", displayTitle: "Other PR", url: "r3"),
    ]
    let snap = buildSnapshot(pr: pr, runs: runs, worktreePath: "/tmp/wt", mainHeadSha: "m1", newMainCommits: [])

    // 1. Prompt-injection filter drops untrusted comments and threads, keeps trusted ones.
    try expect(snap.trustedComments.map(\.author) == ["clinical-pr-shepherd"], "Untrusted comment leaked")
    try expect(snap.unresolvedThreads.map(\.path) == ["C.swift"], "Unexpected unresolved threads: \(snap.unresolvedThreads)")

    // 2. Deduplication keeps latest run per check and supersedes review across workflow suites.
    try expect(snap.checks.count == 2, "Expected 2 deduplicated checks, got \(snap.checks.count)")
    try expect(snap.checks.first { $0.name == "review" }?.conclusion == "SUCCESS", "Newer review should supersede older failure")
    try expect(snap.checks.first { $0.name == "Build" }?.conclusion == "SUCCESS", "Newer Build should supersede older skip")

    // 3. Review loop run filter matches PR title and drops skipped runs.
    try expect(snap.reviewLoopRuns.map(\.databaseId) == [2], "Expected only run 2, got \(snap.reviewLoopRuns)")

    // 4. Worktree porcelain parser prefers branch match and falls back to detached HEAD.
    let porcelain = "worktree /repo/main\nHEAD 111\nbranch refs/heads/main\n\nworktree /repo/wt\nHEAD 222\nbranch refs/heads/feature/sample\n\nworktree /repo/det\nHEAD 333\ndetached"
    try expect(parseWorktreePath(porcelain: porcelain, branch: "feature/sample", headSha: "333") == "/repo/wt", "Should prefer branch")
    try expect(parseWorktreePath(porcelain: porcelain, branch: "other", headSha: "333") == "/repo/det", "Should fall back to HEAD")
}

do { try runAllTests() } catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}

#else

do {
    let testSource = URL(fileURLWithPath: #filePath)
    let dir = testSource.deletingLastPathComponent()
    let tmp = FileManager.default.temporaryDirectory.appending(path: "pr-status-tests-\(UUID())")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let combined = tmp.appending(path: "combined.swift")
    let bin = tmp.appending(path: "tests")
    let impl = try String(contentsOf: dir.appending(path: "pr_status.swift"), encoding: .utf8)
    let tests = try String(contentsOf: testSource, encoding: .utf8)
    try (impl + "\n" + tests).write(to: combined, atomically: true, encoding: .utf8)
    try runCommand(["swiftc", "-D", "PR_STATUS_TESTS", combined.path, "-o", bin.path])
    try runCommand([bin.path])

    // Verify the real CLI compiles and rejects missing arguments cleanly.
    let cli = tmp.appending(path: "cli")
    try runCommand(["swiftc", dir.appending(path: "pr_status.swift").path, "-o", cli.path])
    do {
        try runCommand([cli.path])
        throw TestFailure(description: "CLI accepted missing args.")
    } catch let error as TestFailure {
        try expect(error.description.contains("Usage:"), error.description)
    }

    print("PASS pr_status")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

#endif
