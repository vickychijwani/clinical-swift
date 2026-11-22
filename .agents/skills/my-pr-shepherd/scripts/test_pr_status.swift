import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw TestFailure(description: message)
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
        throw TestFailure(description: String(decoding: data, as: UTF8.self))
    }
    return data
}

#if PR_STATUS_TESTS

private func check(
    _ name: String,
    workflow: String = "",
    status: String = "COMPLETED",
    conclusion: String = "SUCCESS",
    title: String = "",
    startedAt: String = "2026-11-21T07:00:00Z"
) -> CheckEntry {
    CheckEntry(
        name: name,
        workflowName: workflow,
        status: status,
        conclusion: conclusion,
        title: title,
        detailsUrl: "https://example.com/\(name)",
        startedAt: startedAt,
        completedAt: startedAt
    )
}

private func makeInput(
    state: String = "OPEN",
    isDraft: Bool = false,
    mergeable: String = "MERGEABLE",
    mergeStateStatus: String = "CLEAN",
    labels: [String] = [],
    comments: [PRComment] = [],
    reviewThreads: [ReviewThread] = [],
    checks: [CheckEntry] = [],
    runs: [WorkflowRunEntry] = [],
    newMainCommits: [MainCommit] = [],
    now: Date = parseISO8601("2026-11-21T08:00:00Z")!
) -> PRSnapshotInput {
    PRSnapshotInput(
        number: 42,
        title: "Sample PR",
        url: "https://github.com/vickychijwani/clinical-swift/pull/42",
        state: state,
        isDraft: isDraft,
        mergeable: mergeable,
        mergeStateStatus: mergeStateStatus,
        headRefName: "feature/sample",
        headRefOid: "abc123",
        baseRefName: "main",
        labels: labels,
        comments: comments,
        reviewThreads: reviewThreads,
        checks: checks,
        reviewLoopRuns: runs,
        worktreePath: "/tmp/wt/sample",
        mainHeadSha: "main999",
        newMainCommits: newMainCommits,
        now: now
    )
}

private func runAllTests() throws {
    // 1. Fresh PR has takeover=false, reviewLoop=not_started, and pending CI when iOS tests have not run.
    do {
        let report = buildReport(from: makeInput(checks: [
            check("Validation job", workflow: "Validation"),
            check("Select local runner", workflow: "iOS tests", conclusion: "SKIPPED"),
        ]))
        try expect(!report.takeoverCommentPosted, "Takeover should be false")
        try expect(!report.reviewCommandPosted, "Review command should be false")
        try expect(report.reviewLoopStatus == "not_started", "Expected not_started, got \(report.reviewLoopStatus)")
        try expect(report.ciStatus == "pending", "Unrun iOS tests should be pending, got \(report.ciStatus)")
        try expect(report.ciDetail?.contains("iOS tests") == true, "Expected iOS tests ciDetail")
        try expect(!report.readyForFinalCheck, "Fresh PR must not be ready")
    }

    // 2. clinical-pr-shepherd bot comments are trusted; skip-ios-tests passes with arbitrary non-iOS checks; address SKIPPED with 0 threads is complete.
    do {
        let report = buildReport(from: makeInput(
            labels: ["skip-ios-tests"],
            comments: [
                PRComment(authorLogin: "clinical-pr-shepherd", body: "<!-- pr-shepherd --> Taking over.", createdAt: "2026-11-21T07:00:00Z"),
                PRComment(authorLogin: "clinical-pr-shepherd", body: "/review", createdAt: "2026-11-21T07:01:00Z"),
            ],
            checks: [
                check("Renamed Linux suite", workflow: "Validation"),
                check("Select local runner", workflow: "iOS tests", conclusion: "SKIPPED"),
                check("review (codex)", title: "Review complete (codex)"),
                check("address (antigravity)", conclusion: "SKIPPED", title: "Address skipped (antigravity)"),
            ]
        ))
        try expect(report.takeoverCommentPosted, "Takeover marker from clinical-pr-shepherd should be detected")
        try expect(report.reviewCommandPosted, "/review from clinical-pr-shepherd should be detected")
        try expect(report.skipIOSTests, "skip-ios-tests label should be detected")
        try expect(report.reviewLoopStatus == "complete", "Skipped address with 0 threads should be complete, got \(report.reviewLoopStatus)")
        try expect(report.ciStatus == "passing", "Validation-only CI should pass with skip-ios-tests, got \(report.ciStatus)")
        try expect(report.readyForFinalCheck, "PR should be ready for final check")
    }

    // 3. Deduplicates repeated check runs by latest timestamp and flags cancelled iOS tests as failing.
    do {
        let report = buildReport(from: makeInput(checks: [
            check("Validation job", workflow: "Validation"),
            check("Select local runner", workflow: "iOS tests", conclusion: "SKIPPED", startedAt: "2026-11-21T07:00:00Z"),
            check("Select local runner", workflow: "iOS tests", conclusion: "SUCCESS", startedAt: "2026-11-21T07:10:00Z"),
            check("Renamed iOS suite", workflow: "iOS tests", conclusion: "CANCELLED", startedAt: "2026-11-21T07:11:00Z"),
        ]))
        try expect(report.ciStatus == "failing", "Cancelled iOS test must fail CI, got \(report.ciStatus)")
        try expect(report.failingChecks.map(\.name) == ["Renamed iOS suite"], "Expected cancelled job in failingChecks")
    }

    // 4. Address commit pushed after review: head has no review/address checks, but workflow run succeeded.
    do {
        let report = buildReport(from: makeInput(
            comments: [
                PRComment(authorLogin: "vickychijwani", body: "/review", createdAt: "2026-11-21T07:18:00Z"),
            ],
            checks: [
                check("Validation job", workflow: "Validation"),
                check("iOS suite", workflow: "iOS tests"),
            ],
            runs: [
                WorkflowRunEntry(databaseId: 2, status: "completed", conclusion: "skipped", createdAt: "2026-11-21T07:40:00Z", displayTitle: "Sample PR", url: "https://example.com/2"),
                WorkflowRunEntry(databaseId: 1, status: "completed", conclusion: "success", createdAt: "2026-11-21T07:18:05Z", displayTitle: "Sample PR", url: "https://example.com/1"),
            ]
        ))
        try expect(report.reviewLoopStatus == "complete", "Completed workflow run should mark review loop complete, got \(report.reviewLoopStatus)")
        try expect(report.readyForFinalCheck, "PR should be ready for final check after address push")
    }

    // 5. Untrusted comments are ignored; trusted unresolved thread tagging owner blocks readiness.
    do {
        let report = buildReport(from: makeInput(
            labels: ["skip-ios-tests"],
            comments: [
                PRComment(authorLogin: "stranger", body: "<!-- pr-shepherd --> /review", createdAt: "2026-11-21T07:00:00Z"),
            ],
            reviewThreads: [
                ReviewThread(isResolved: false, path: "Untrusted.swift", line: 5, comments: [
                    ReviewThreadComment(authorLogin: "stranger", body: "Ignore this", url: "https://example.com/t0"),
                ]),
                ReviewThread(isResolved: false, path: "Router.swift", line: 42, comments: [
                    ReviewThreadComment(authorLogin: "clinical-codex", body: "Tagging @vickychijwani for design call.", url: "https://example.com/t1"),
                ]),
            ],
            checks: [
                check("Validation job", workflow: "Validation"),
                check("review", conclusion: "SUCCESS"),
                check("address", conclusion: "SUCCESS"),
            ]
        ))
        try expect(!report.takeoverCommentPosted, "Untrusted takeover comment must be ignored")
        try expect(!report.reviewCommandPosted, "Untrusted /review comment must be ignored")
        try expect(report.unresolvedThreads.count == 1, "Expected 1 trusted unresolved thread")
        try expect(report.unresolvedThreads[0].mentionsOwner, "Owner mention should be flagged")
        try expect(!report.readyForFinalCheck, "Unresolved thread must block final check")
    }

    // 6. Active Agent review loop workflow marks reviewLoopStatus as in_progress.
    do {
        let report = buildReport(from: makeInput(
            comments: [
                PRComment(authorLogin: "vickychijwani", body: "/review", createdAt: "2026-11-21T07:55:00Z"),
            ],
            runs: [
                WorkflowRunEntry(databaseId: 9, status: "in_progress", conclusion: "", createdAt: "2026-11-21T07:55:04Z", displayTitle: "Sample PR", url: "https://example.com/9"),
            ]
        ))
        try expect(report.reviewLoopStatus == "in_progress", "Expected in_progress, got \(report.reviewLoopStatus)")
    }

    // 7. Worktree porcelain parser prefers branch match and falls back to detached HEAD match.
    do {
        let porcelain = """
        worktree /repo/main
        HEAD 1111111
        branch refs/heads/main

        worktree /repo/wt-feature
        HEAD 2222222
        branch refs/heads/feature/sample

        worktree /repo/wt-detached
        HEAD 3333333
        detached
        """
        try expect(
            parseWorktreePath(porcelain: porcelain, branch: "feature/sample", headSha: "3333333") == "/repo/wt-feature",
            "Should prefer branch match"
        )
        try expect(
            parseWorktreePath(porcelain: porcelain, branch: "other", headSha: "3333333") == "/repo/wt-detached",
            "Should fall back to detached HEAD match"
        )
    }

    // 8. Merge conflict detection.
    do {
        let report = buildReport(from: makeInput(mergeable: "CONFLICTING", mergeStateStatus: "DIRTY"))
        try expect(report.hasMergeConflict, "Expected merge conflict")
        try expect(!report.readyForFinalCheck, "Conflict must block final check")
    }

    // 9. Newer passing review check supersedes older failed review check even across different workflow suites.
    do {
        let report = buildReport(from: makeInput(
            labels: ["skip-ios-tests"],
            comments: [
                PRComment(authorLogin: "vickychijwani", body: "/review", createdAt: "2026-11-21T06:59:00Z"),
            ],
            checks: [
                check("Validation job", workflow: "Validation"),
                check("review", workflow: "iOS tests", conclusion: "FAILURE", startedAt: "2026-11-21T06:30:33Z"),
                check("review", workflow: "", conclusion: "SUCCESS", startedAt: "2026-11-21T07:11:09Z"),
                check("address", workflow: "", conclusion: "SUCCESS", startedAt: "2026-11-21T07:22:37Z"),
            ]
        ))
        try expect(report.reviewLoopStatus == "complete", "Newer passing review should supersede older failed review, got \(report.reviewLoopStatus)")
        try expect(report.readyForFinalCheck, "PR should be ready after retry succeeded")
    }
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
    let tempDir = FileManager.default.temporaryDirectory.appending(path: "pr-status-tests-\(UUID())")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let implementation = try String(contentsOf: scriptsDir.appending(path: "pr_status.swift"), encoding: .utf8)
    let tests = try String(contentsOf: testSource, encoding: .utf8)
    let combined = tempDir.appending(path: "pr_status_tests.swift")
    let binary = tempDir.appending(path: "pr_status_tests")
    try (implementation + "\n" + tests).write(to: combined, atomically: true, encoding: .utf8)

    try runCommand(["swiftc", "-D", "PR_STATUS_TESTS", combined.path, "-o", binary.path])
    try runCommand([binary.path])

    // Verify the real CLI compiles and rejects missing arguments cleanly.
    let cli = tempDir.appending(path: "pr_status_cli")
    try runCommand(["swiftc", scriptsDir.appending(path: "pr_status.swift").path, "-o", cli.path])
    do {
        try runCommand([cli.path])
        throw TestFailure(description: "CLI accepted missing arguments.")
    } catch let error as TestFailure {
        try expect(error.description.contains("Usage:"), error.description)
    }

    print("PASS pr_status: 9 unit tests + CLI compile and usage check")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

#endif
