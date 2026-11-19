import Foundation
import SQLite3

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw TestFailure(description: message)
    }
}

private func runGit(_ repo: String, _ args: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", repo] + args
    process.standardInput = FileHandle.nullDevice
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    try process.run()
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw TestFailure(
            description:
                "git \(args.joined(separator: " ")) failed: \(String(decoding: errData, as: UTF8.self))"
        )
    }
    return String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func createSuperDB(
    at path: String, rows: [(provider: String, worktree: String, updatedAt: Int)]
) throws {
    var db: OpaquePointer?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
        let db
    else {
        if let db { sqlite3_close(db) }
        throw TestFailure(description: "Could not create test SQLite DB at \(path)")
    }
    defer { sqlite3_close(db) }

    let createSQL = """
        CREATE TABLE conversations (
            conversation_id TEXT PRIMARY KEY,
            provider_key TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            metadata TEXT
        );
        """
    guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
        throw TestFailure(description: "Failed creating conversations table")
    }

    let insertSQL = "INSERT INTO conversations VALUES (?, ?, ?, ?, ?);"
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, row) in rows.enumerated() {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw TestFailure(description: "Failed preparing insert")
        }
        defer { sqlite3_finalize(stmt) }
        let metadataData = try JSONSerialization.data(withJSONObject: [
            "worktree_path": row.worktree
        ])
        let metadata = String(decoding: metadataData, as: UTF8.self)
        sqlite3_bind_text(stmt, 1, "conv-\(index)", -1, transient)
        sqlite3_bind_text(stmt, 2, row.provider, -1, transient)
        sqlite3_bind_int64(stmt, 3, Int64(row.updatedAt))
        sqlite3_bind_int64(stmt, 4, Int64(row.updatedAt))
        sqlite3_bind_text(stmt, 5, metadata, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw TestFailure(description: "Failed inserting row \(index)")
        }
    }
}

#if AGENT_REVIEW_LOOP_TESTS
    private func testParseTrigger() throws {
        try expect(
            parseTrigger(eventName: "issue_comment", commentBody: "/review")
                == TriggerPlan(action: .review, prNumber: nil, reviewerOverride: nil, dryRun: false),
            "/review should parse"
        )
        try expect(
            parseTrigger(eventName: "issue_comment", commentBody: "  /review   codex \n")
                == TriggerPlan(
                    action: .review, prNumber: nil, reviewerOverride: .codex, dryRun: false),
            "/review codex should trim whitespace"
        )
        try expect(
            parseTrigger(eventName: "issue_comment", commentBody: "/review antigravity")
                == TriggerPlan(
                    action: .review, prNumber: nil, reviewerOverride: .antigravity, dryRun: false),
            "/review antigravity should parse"
        )
        try expect(
            parseTrigger(eventName: "issue_comment", commentBody: "/address\n")
                == TriggerPlan(
                    action: .address, prNumber: nil, reviewerOverride: nil, dryRun: false),
            "/address should parse"
        )
        try expect(
            parseTrigger(
                eventName: "workflow_dispatch",
                dispatchAction: "review",
                dispatchReviewer: "auto",
                dispatchPRNumber: "28",
                dispatchDryRun: "true"
            ) == TriggerPlan(action: .review, prNumber: 28, reviewerOverride: nil, dryRun: true),
            "workflow_dispatch auto dry_run should parse"
        )

        for invalid in [
            "", "/review claude", "/review codex extra", "/address codex", "looks good",
        ] {
            do {
                _ = try parseTrigger(eventName: "issue_comment", commentBody: invalid)
                throw TestFailure(description: "Should reject comment '\(invalid)'")
            } catch is ReviewLoopError {}
        }
    }

    private func testParseMention() throws {
        try expect(
            parseMention(
                eventName: "issue_comment", commentBody: "@clinical-codex fix the failing test")
                == MentionPlan(
                    matched: true,
                    harness: .codex,
                    prNumber: nil,
                    instructions: "@clinical-codex fix the failing test",
                    dryRun: false
                ),
            "Start mention should match codex"
        )
        try expect(
            parseMention(
                eventName: "pull_request_review_comment",
                commentBody: "Please rename this helper @Clinical-Antigravity[bot]"
            )
                == MentionPlan(
                    matched: true,
                    harness: .antigravity,
                    prNumber: nil,
                    instructions: "Please rename this helper @Clinical-Antigravity[bot]",
                    dryRun: false
                ),
            "Mid/end mention with [bot] should match antigravity case-insensitively"
        )
        try expect(
            parseMention(
                eventName: "pull_request_review",
                commentBody:
                    "> @clinical-codex earlier note\n\n@clinical-antigravity please handle this"
            )
                == MentionPlan(
                    matched: true,
                    harness: .antigravity,
                    prNumber: nil,
                    instructions:
                        "> @clinical-codex earlier note\n\n@clinical-antigravity please handle this",
                    dryRun: false
                ),
            "Quoted mention of the other bot must be ignored"
        )
        try expect(
            parseMention(
                eventName: "issue_comment",
                commentBody: "@clinical-codex\n```swift\nlet x = 1\n```"
            ).matched == true,
            "Code block instructions after tag should count as valid instructions"
        )
        try expect(
            parseMention(
                eventName: "issue_comment",
                commentBody: "---\n@clinical-codex\nplease check"
            ).harness == .codex,
            "Multiline comment starting with -- should parse cleanly"
        )

        for nonMatch in [
            "",
            "looks good",
            "email user@clinical-codex.com",
            "@clinical-codex-v2 do something",
            "@clinical-codex[other] do something",
            "Use `@clinical-codex` to wake up the bot",
            "```\n@clinical-antigravity\n```",
            "> @clinical-codex fix this",
        ] {
            let plan = try parseMention(eventName: "issue_comment", commentBody: nonMatch)
            try expect(!plan.matched, "Comment '\(nonMatch)' must not match a bot tag")
        }

        for invalid in [
            "@clinical-codex @clinical-antigravity do this",
            "@clinical-codex[bot] and @clinical-antigravity",
            "@clinical-codex",
            "@clinical-antigravity[bot]:   ",
            "> @clinical-antigravity old\n\n@clinical-codex",
        ] {
            do {
                _ = try parseMention(eventName: "issue_comment", commentBody: invalid)
                throw TestFailure(description: "Should reject invalid mention comment '\(invalid)'")
            } catch is ReviewLoopError {}
        }

        try expect(
            parseMention(
                eventName: "workflow_dispatch",
                dispatchBot: "antigravity",
                dispatchInstructions: "Update the docs",
                dispatchPRNumber: "31",
                dispatchDryRun: "true"
            )
                == MentionPlan(
                    matched: true,
                    harness: .antigravity,
                    prNumber: 31,
                    instructions: "Update the docs",
                    dryRun: true
                ),
            "workflow_dispatch mention should parse"
        )
    }

    private func testWorktreeClassificationAndParsing() throws {
        let home = "/Users/tester"
        try expect(
            classifyWorktreePath(
                "/Users/tester/.codex/worktrees/0d2c/clinical-swift", homeDirectory: home)
                == .codex,
            "Codex path should classify"
        )
        try expect(
            classifyWorktreePath(
                "/Users/tester/.gemini/antigravity/worktrees/clinical-swift/my_branch",
                homeDirectory: home)
                == .antigravity,
            "Antigravity path should classify"
        )
        try expect(
            classifyWorktreePath(
                "/Users/tester/.super.engineering/worktrees/clinical-swift/sc-vortex",
                homeDirectory: home)
                == .superEngineering,
            "super.engineering path should classify"
        )
        try expect(
            classifyWorktreePath("/Users/tester/code/clinical-swift", homeDirectory: home)
                == .unknown,
            "Main repo path should classify as unknown"
        )
        try expect(
            classifyWorktreePath("/private/tmp/clinical-pr28-review", homeDirectory: home)
                == .unknown,
            "Temp checkout path should classify as unknown"
        )

        let porcelain = """
            worktree /Users/tester/code/clinical-swift
            HEAD 1111111
            branch refs/heads/main

            worktree /Users/tester/.codex/worktrees/abcd/clinical-swift
            HEAD 2222222
            detached
            locked initializing

            worktree /private/tmp/review
            HEAD 2222222
            detached
            """
        let entries = parseWorktreeList(porcelain)
        try expect(entries.count == 3, "Expected 3 parsed entries")
        let located = try locateWorktree(
            entries: entries, branch: "missing-branch", headSHA: "2222222", homeDirectory: home)
        try expect(
            located?.path == "/Users/tester/.codex/worktrees/abcd/clinical-swift",
            "Detached fallback should ignore /private/tmp and pick author root"
        )
    }

    private func testDiscoveryIntegration(in root: URL) throws {
        let fm = FileManager.default
        let home = root.appending(path: "home")
        let canonical = home.appending(path: "code/clinical-swift")
        try fm.createDirectory(at: canonical, withIntermediateDirectories: true)

        _ = try runGit(canonical.path, ["init", "-b", "main"])
        _ = try runGit(canonical.path, ["config", "user.name", "Tester"])
        _ = try runGit(canonical.path, ["config", "user.email", "tester@example.com"])
        try Data("base\n".utf8).write(to: canonical.appending(path: "README.md"))
        _ = try runGit(canonical.path, ["add", "README.md"])
        _ = try runGit(canonical.path, ["commit", "-m", "Initial commit"])
        let baseSHA = try runGit(canonical.path, ["rev-parse", "HEAD"])

        // Create Codex detached worktree at baseSHA + commit on codex branch.
        let codexWT = home.appending(path: ".codex/worktrees/0d2c/clinical-swift")
        try fm.createDirectory(
            at: codexWT.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try runGit(canonical.path, ["worktree", "add", "--detach", codexWT.path, baseSHA])

        let agyWT = home.appending(path: ".gemini/antigravity/worktrees/clinical-swift/feature_one")
        try fm.createDirectory(
            at: agyWT.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try runGit(
            canonical.path, ["worktree", "add", "-b", "feature_one", agyWT.path, baseSHA])
        try Data("agy\n".utf8).write(to: agyWT.appending(path: "agy.txt"))
        _ = try runGit(agyWT.path, ["add", "agy.txt"])
        _ = try runGit(agyWT.path, ["commit", "-m", "Agy change"])
        let agySHA = try runGit(agyWT.path, ["rev-parse", "HEAD"])

        let superWT = home.appending(path: ".super.engineering/worktrees/clinical-swift/sc-1")
        try fm.createDirectory(
            at: superWT.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try runGit(
            canonical.path, ["worktree", "add", "-b", "codex/super-branch", superWT.path, baseSHA])
        try Data("super\n".utf8).write(to: superWT.appending(path: "super.txt"))
        _ = try runGit(superWT.path, ["add", "super.txt"])
        _ = try runGit(superWT.path, ["commit", "-m", "Super change"])
        let superSHA = try runGit(superWT.path, ["rev-parse", "HEAD"])

        let dbPath = root.appending(path: "super.db").path
        let resolvedSuperWT = superWT.standardizedFileURL.resolvingSymlinksInPath().path
        try createSuperDB(
            at: dbPath,
            rows: [
                (provider: "claude", worktree: resolvedSuperWT, updatedAt: 100),
                (provider: "codex", worktree: resolvedSuperWT, updatedAt: 200),
            ]
        )

        // 1. Codex detached worktree discovery.
        let codexRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "codex/detached-pr",
            headSHA: baseSHA,
            action: .review,
            reviewerOverride: nil,
            superDBPath: dbPath,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            codexRes.status == "ok",
            "Codex detached worktree should succeed: \(codexRes.error ?? "")")
        try expect(codexRes.authorHarness == .codex, "Expected codex author")
        try expect(codexRes.reviewerHarness == .antigravity, "Expected antigravity reviewer")

        // 2. Antigravity worktree discovery.
        let agyRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "feature_one",
            headSHA: agySHA,
            action: .review,
            reviewerOverride: nil,
            superDBPath: dbPath,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(agyRes.status == "ok", "Antigravity worktree should succeed")
        try expect(agyRes.authorHarness == .antigravity, "Expected antigravity author")
        try expect(agyRes.reviewerHarness == .codex, "Expected codex reviewer")

        // 3. super.engineering with multiple providers picks latest (codex) and adds note.
        let superRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "codex/super-branch",
            headSHA: superSHA,
            action: .review,
            reviewerOverride: nil,
            superDBPath: dbPath,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(superRes.status == "ok", "super.engineering codex worktree should succeed")
        try expect(superRes.authorHarness == .codex, "Expected codex author from super DB")
        try expect(
            superRes.notes.contains(where: { $0.contains("Multiple super.engineering providers") }),
            "Expected multiple-provider log note"
        )

        // 4. Non-codex super.engineering provider stops when no override.
        let claudeDBPath = root.appending(path: "super-claude.db").path
        try createSuperDB(
            at: claudeDBPath,
            rows: [(provider: "claude", worktree: resolvedSuperWT, updatedAt: 300)]
        )
        let claudeRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "codex/super-branch",
            headSHA: superSHA,
            action: .review,
            reviewerOverride: nil,
            superDBPath: claudeDBPath,
            homeDirectory: home.path,
            requireClean: false
        )
        try expect(claudeRes.status == "error", "Non-codex super.engineering provider must stop")

        // 5. /review <reviewer> override falls back to other harness for unknown path.
        let overrideRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "main",
            headSHA: baseSHA,
            action: .review,
            reviewerOverride: .codex,
            superDBPath: dbPath,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(overrideRes.status == "ok", "Override should allow unknown path")
        try expect(overrideRes.reviewerHarness == .codex, "Override reviewer should be codex")
        try expect(
            overrideRes.authorHarness == .antigravity,
            "Override fallback author should be antigravity")

        // 6. --require-clean catches stale HEAD and dirty working tree.
        let staleRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "feature_one",
            headSHA: baseSHA,
            action: .address,
            reviewerOverride: nil,
            superDBPath: dbPath,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            staleRes.status == "error" && (staleRes.error ?? "").contains("HEAD"),
            "Stale HEAD must fail")

        try Data("dirty\n".utf8).write(to: agyWT.appending(path: "untracked.txt"))
        let dirtyRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "feature_one",
            headSHA: agySHA,
            action: .address,
            reviewerOverride: nil,
            superDBPath: dbPath,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            dirtyRes.status == "error" && (dirtyRes.error ?? "").contains("uncommitted"),
            "Dirty worktree must fail"
        )

        // 7. Mention discovery accepts explicit cross-harness bot on any located PR worktree.
        let mentionCrossRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "codex/detached-pr",
            headSHA: baseSHA,
            action: .mention,
            reviewerOverride: nil,
            targetHarness: .antigravity,
            superDBPath: dbPath,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            mentionCrossRes.status == "ok"
                && mentionCrossRes.authorHarness == .antigravity
                && mentionCrossRes.worktreePath != nil,
            "Mention discovery should allow @clinical-antigravity in a Codex worktree"
        )

        let mentionSuperRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "codex/super-branch",
            headSHA: superSHA,
            action: .mention,
            reviewerOverride: nil,
            targetHarness: .codex,
            superDBPath: claudeDBPath,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            mentionSuperRes.status == "ok" && mentionSuperRes.authorHarness == .codex,
            "Mention discovery should work on super.engineering worktree regardless of DB provider"
        )

        let mentionMissingRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "missing-branch",
            headSHA: "deadbeef",
            action: .mention,
            reviewerOverride: nil,
            targetHarness: .codex,
            superDBPath: dbPath,
            homeDirectory: home.path,
            requireClean: false
        )
        try expect(
            mentionMissingRes.status == "error",
            "Mention discovery without a local worktree must fail even when requireClean is false"
        )
    }

    private func testCodexSkillsConfig(in root: URL) throws {
        let fm = FileManager.default
        let repo = root.appending(path: "skills-repo")
        let home = root.appending(path: "skills-home")
        for rel in [
            "skills-repo/.agents/skills/my-review",
            "skills-repo/.agents/skills/my-design-review",
            "skills-repo/.agents/skills/my-address-review",
            "skills-repo/.codex/skills/my-comments",
            "skills-home/.codex/skills/hatch-pet",
            "skills-home/.codex/skills/.system/imagegen",
            "skills-home/.agents/skills/rex",
        ] {
            let dir = root.appending(path: rel)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("# skill\n".utf8).write(to: dir.appending(path: "SKILL.md"))
        }

        let config = buildCodexSkillsConfig(
            repoPath: repo.path,
            homeDirectory: home.path,
            allowedNames: ["my-review", "my-design-review"]
        )
        try expect(
            !config.contains("my-review/SKILL.md"), "Allowlisted my-review must stay enabled")
        try expect(
            !config.contains("my-design-review/SKILL.md"),
            "Allowlisted my-design-review must stay enabled")
        try expect(
            config.contains("my-address-review/SKILL.md"),
            "my-address-review must be disabled for reviewer")
        try expect(config.contains("my-comments/SKILL.md"), "my-comments must be disabled")
        try expect(config.contains("hatch-pet/SKILL.md"), "User skill must be disabled")
        try expect(config.contains("imagegen/SKILL.md"), "System skill must be disabled")
        try expect(config.contains("rex/SKILL.md"), "Home .agents skill must be disabled")
    }

    private func testCheckRunPayload() throws {
        let queued = try buildCheckRunPayload(
            name: "review",
            headSHA: "abc123",
            status: .queued,
            title: "Queued (antigravity)",
            summary: "Waiting for runner",
            detailsURL: "https://github.com/vickychijwani/clinical-swift/actions/runs/1",
            externalID: "1-review",
            timestamp: "2026-11-18T00:00:00Z"
        )
        try expect(queued.status == .queued, "Queued status mismatch")
        try expect(queued.headSHA == "abc123", "Queued head_sha mismatch")
        try expect(
            queued.startedAt == nil && queued.completedAt == nil, "Queued must omit timestamps")
        try expect(queued.conclusion == nil, "Queued must omit conclusion")

        let inProgress = try buildCheckRunPayload(
            status: .inProgress,
            title: "Reviewing PR (antigravity)",
            summary: "Running agent",
            timestamp: "2026-11-18T00:01:00Z"
        )
        try expect(
            inProgress.startedAt == "2026-11-18T00:01:00Z", "In-progress must set started_at")
        try expect(inProgress.completedAt == nil, "In-progress must omit completed_at")

        let completed = try buildCheckRunPayload(
            status: .completed,
            conclusion: "success",
            title: "Review complete",
            summary: "Done",
            timestamp: "2026-11-18T00:02:00Z"
        )
        try expect(
            completed.completedAt == "2026-11-18T00:02:00Z", "Completed must set completed_at")
        try expect(completed.conclusion == "success", "Completed must set conclusion")

        var rejectedMissingConclusion = false
        do {
            _ = try buildCheckRunPayload(status: .completed)
        } catch {
            rejectedMissingConclusion = true
        }
        try expect(rejectedMissingConclusion, "Completed check run without conclusion must throw")

        var rejectedUnexpectedConclusion = false
        do {
            _ = try buildCheckRunPayload(status: .queued, conclusion: "success")
        } catch {
            rejectedUnexpectedConclusion = true
        }
        try expect(
            rejectedUnexpectedConclusion, "Non-completed check run with conclusion must throw")
    }

    private func testMonitorRecord(in root: URL) throws {
        let monitorDir = root.appending(path: "monitor", directoryHint: .isDirectory)

        try recordMonitorState(
            monitorDirectory: monitorDir.path,
            runID: "999",
            kind: "review-loop",
            phase: .review,
            prNumber: 33,
            prBranch: "overlay_toast_widget",
            prHeadSHA: "abc123",
            repository: "vickychijwani/clinical-swift",
            runURL: "https://github.com/vickychijwani/clinical-swift/actions/runs/999",
            harness: .codex,
            status: .queued,
            timestamp: "2026-11-19T08:00:00Z"
        )

        try recordMonitorState(
            monitorDirectory: monitorDir.path,
            runID: "999",
            phase: .review,
            botLogin: "clinical-codex[bot]",
            model: "gpt-6.1-sol",
            effort: "high",
            worktreePath: "/tmp/pr",
            prompt: "Review PR #33",
            streamFile: monitorDir.appending(path: "runs/999/review.jsonl").path,
            status: .running,
            timestamp: "2026-11-19T08:01:00Z"
        )

        try recordMonitorState(
            monitorDirectory: monitorDir.path,
            runID: "999",
            phase: .review,
            status: .completed,
            conclusion: "success",
            timestamp: "2026-11-19T08:03:00Z"
        )

        let runData = try Data(contentsOf: monitorDir.appending(path: "runs/999/run.json"))
        let runRecord = try JSONDecoder().decode(MonitorRunRecord.self, from: runData)
        try expect(runRecord.prNumber == 33, "Expected prNumber preserved")
        try expect(runRecord.createdAt == "2026-11-19T08:00:00Z", "Expected createdAt preserved")
        try expect(runRecord.updatedAt == "2026-11-19T08:03:00Z", "Expected updatedAt updated")

        let phaseData = try Data(contentsOf: monitorDir.appending(path: "runs/999/review.json"))
        let phaseRecord = try JSONDecoder().decode(MonitorPhaseRecord.self, from: phaseData)
        try expect(phaseRecord.harness == .codex, "Expected harness preserved across updates")
        try expect(phaseRecord.prompt == "Review PR #33", "Expected prompt preserved across updates")
        try expect(phaseRecord.startedAt == "2026-11-19T08:01:00Z", "Expected startedAt preserved")
        try expect(phaseRecord.completedAt == "2026-11-19T08:03:00Z", "Expected completedAt set")
        try expect(phaseRecord.conclusion == "success", "Expected conclusion recorded")
    }

    private func runAllTests() {
        let tempRoot = FileManager.default.temporaryDirectory.appending(
            path: "agent-review-loop-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        do {
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            try testParseTrigger()
            try testParseMention()
            try testWorktreeClassificationAndParsing()
            try testDiscoveryIntegration(in: tempRoot)
            try testCodexSkillsConfig(in: tempRoot)
            try testCheckRunPayload()
            try testMonitorRecord(in: tempRoot)
            print("PASS agent review loop unit and integration tests")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    runAllTests()
#else
    private func runShell(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TestFailure(
                description:
                    "\(args.joined(separator: " ")) failed: \(String(decoding: err, as: UTF8.self))"
            )
        }
        return String(decoding: out, as: UTF8.self)
    }

    do {
        let testSource = URL(fileURLWithPath: #filePath)
        let scriptsDir = testSource.deletingLastPathComponent()
        let sourceURL = scriptsDir.appending(path: "agent_review_loop.swift")
        let tempDir = FileManager.default.temporaryDirectory.appending(
            path: "agent-review-loop-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let implementation = try String(contentsOf: sourceURL, encoding: .utf8)
        let tests = try String(contentsOf: testSource, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("import ") }
            .joined(separator: "\n")

        let combined = tempDir.appending(path: "combined.swift")
        let testBinary = tempDir.appending(path: "test_binary")
        try (implementation + "\n" + tests).write(to: combined, atomically: true, encoding: .utf8)
        _ = try runShell([
            "swiftc", "-D", "AGENT_REVIEW_LOOP_TESTS", combined.path, "-o", testBinary.path,
        ])
        print(try runShell([testBinary.path]).trimmingCharacters(in: .whitespacesAndNewlines))

        let cliBinary = tempDir.appending(path: "cli_binary")
        _ = try runShell(["swiftc", sourceURL.path, "-o", cliBinary.path])
        let triggerOut = try runShell([
            cliBinary.path, "parse-trigger", "--event", "issue_comment", "--body", "/review codex",
        ])
        try expect(
            triggerOut.contains("\"reviewerOverride\":\"codex\""), "CLI parse-trigger failed")
        let mentionOut = try runShell([
            cliBinary.path, "parse-mention", "--event", "issue_comment", "--body",
            "---\n@clinical-antigravity fix it",
        ])
        try expect(
            mentionOut.contains("\"matched\":true")
                && mentionOut.contains("\"harness\":\"antigravity\""),
            "CLI parse-mention failed"
        )
        let monitorDir = tempDir.appending(path: "cli-monitor")
        _ = try runShell([
            cliBinary.path, "monitor-record",
            "--monitor-dir", monitorDir.path,
            "--run-id", "42",
            "--phase", "bot",
            "--harness", "antigravity",
            "--status", "queued",
        ])
        try expect(
            FileManager.default.fileExists(atPath: monitorDir.appending(path: "runs/42/bot.json").path),
            "CLI monitor-record failed"
        )
        print("PASS agent review loop CLI compilation and smoke check")
    } catch {
        FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
        exit(1)
    }
#endif
