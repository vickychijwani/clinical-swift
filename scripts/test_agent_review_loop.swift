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

private func createAgyConversationDB(
    at agyDir: URL,
    rows: [(convID: String, worktree: String, modifiedTime: String, model: String?)]
) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: agyDir, withIntermediateDirectories: true)
    let dbPath = agyDir.appending(path: "conversation_summaries.db").path

    var db: OpaquePointer?
    guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
        let db
    else {
        if let db { sqlite3_close(db) }
        throw TestFailure(description: "Could not create test Antigravity DB at \(dbPath)")
    }
    defer { sqlite3_close(db) }

    let createSQL = """
        CREATE TABLE conversation_summaries (
            conversation_id TEXT PRIMARY KEY,
            last_modified_time TEXT NOT NULL,
            workspace_uris TEXT NOT NULL
        );
        """
    guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
        throw TestFailure(description: "Failed creating conversation_summaries table")
    }

    let insertSQL = "INSERT INTO conversation_summaries VALUES (?, ?, ?);"
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for row in rows {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw TestFailure(description: "Failed preparing Antigravity insert")
        }
        defer { sqlite3_finalize(stmt) }
        let urisData = try JSONEncoder().encode([URL(fileURLWithPath: row.worktree).absoluteString])
        let uris = String(decoding: urisData, as: UTF8.self)
        sqlite3_bind_text(stmt, 1, row.convID, -1, transient)
        sqlite3_bind_text(stmt, 2, row.modifiedTime, -1, transient)
        sqlite3_bind_text(stmt, 3, uris, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw TestFailure(description: "Failed inserting Antigravity row \(row.convID)")
        }

        if let model = row.model {
            let logsDir = agyDir.appending(
                path: "brain/\(row.convID)/.system_generated/logs", directoryHint: .isDirectory)
            try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
            let transcript = """
                {"step_index":0,"type":"USER_INPUT","content":"hello"}
                {"step_index":1,"type":"PLANNER_RESPONSE","model":"\(model)","content":"done"}
                """
            try transcript.write(
                to: logsDir.appending(path: "transcript.jsonl"), atomically: true, encoding: .utf8)
        }
    }
}

#if AGENT_REVIEW_LOOP_TESTS
    private func testParseTrigger() throws {
        try expect(
            parseTrigger(eventName: "issue_comment", commentBody: "/review")
                == TriggerPlan(
                    action: .review,
                    prNumber: nil,
                    reviewerOverride: nil,
                    reviewAll: false,
                    authorOverride: nil,
                    dryRun: false
                ),
            "/review should parse"
        )
        try expect(
            parseTrigger(eventName: "issue_comment", commentBody: "  /review   sol \n")
                == TriggerPlan(
                    action: .review,
                    prNumber: nil,
                    reviewerOverride: [.sol],
                    reviewAll: false,
                    authorOverride: nil,
                    dryRun: false
                ),
            "/review sol should trim whitespace"
        )
        try expect(
            parseTrigger(eventName: "issue_comment", commentBody: "/review opus sol opus hydrogen")
                == TriggerPlan(
                    action: .review,
                    prNumber: nil,
                    reviewerOverride: [.opus, .sol, .hydrogen],
                    reviewAll: false,
                    authorOverride: nil,
                    dryRun: false
                ),
            "Multi-reviewer /review should preserve order and deduplicate"
        )
        try expect(
            parseTrigger(eventName: "issue_comment", commentBody: "/review all")
                == TriggerPlan(
                    action: .review,
                    prNumber: nil,
                    reviewerOverride: nil,
                    reviewAll: true,
                    authorOverride: nil,
                    dryRun: false
                ),
            "/review all should set reviewAll"
        )
        try expect(
            parseTrigger(eventName: "issue_comment", commentBody: "/address\n")
                == TriggerPlan(
                    action: .address,
                    prNumber: nil,
                    reviewerOverride: nil,
                    reviewAll: false,
                    authorOverride: nil,
                    dryRun: false
                ),
            "/address should parse"
        )
        try expect(
            parseTrigger(eventName: "issue_comment", commentBody: "/address opus")
                == TriggerPlan(
                    action: .address,
                    prNumber: nil,
                    reviewerOverride: nil,
                    reviewAll: false,
                    authorOverride: .opus,
                    dryRun: false
                ),
            "/address opus should parse author override"
        )
        try expect(
            parseTrigger(
                eventName: "workflow_dispatch",
                dispatchAction: "review",
                dispatchReviewer: "all",
                dispatchAuthor: "neon",
                dispatchPRNumber: "28",
                dispatchDryRun: "true"
            )
                == TriggerPlan(
                    action: .review,
                    prNumber: 28,
                    reviewerOverride: nil,
                    reviewAll: true,
                    authorOverride: .neon,
                    dryRun: true
                ),
            "workflow_dispatch all with author override should parse"
        )

        for invalid in [
            "", "/review codex", "/review antigravity", "/review all opus", "/review sol extra",
            "/address codex", "/address sol opus", "looks good",
        ] {
            do {
                _ = try parseTrigger(eventName: "issue_comment", commentBody: invalid)
                throw TestFailure(description: "Should reject comment '\(invalid)'")
            } catch is ReviewLoopError {}
        }
    }

    private func testParseAsk() throws {
        try expect(
            parseAsk(eventName: "issue_comment", commentBody: "/ask fix the failing test")
                == AskPlan(
                    matched: true,
                    modelOverride: nil,
                    prNumber: nil,
                    instructions: "fix the failing test",
                    dryRun: false
                ),
            "Bare /ask should default to auto author model"
        )
        try expect(
            parseAsk(
                eventName: "pull_request_review_comment",
                commentBody: "/ask opus please rename this helper"
            )
                == AskPlan(
                    matched: true,
                    modelOverride: .opus,
                    prNumber: nil,
                    instructions: "please rename this helper",
                    dryRun: false
                ),
            "/ask opus should extract model override and instructions"
        )
        try expect(
            parseAsk(
                eventName: "pull_request_review",
                commentBody: "  /ask   Hydrogen\ncheck line 42"
            )
                == AskPlan(
                    matched: true,
                    modelOverride: .hydrogen,
                    prNumber: nil,
                    instructions: "check line 42",
                    dryRun: false
                ),
            "/ask should accept case-insensitive model name and multiline instructions"
        )

        for nonMatch in [
            "",
            "looks good",
            "/asking about this",
            "@clinical-codex fix this",
            "@clinical-antigravity fix this",
            "Use /ask opus to run opus",
        ] {
            let plan = try parseAsk(eventName: "issue_comment", commentBody: nonMatch)
            try expect(!plan.matched, "Comment '\(nonMatch)' must not match /ask")
        }

        for invalid in [
            "/ask",
            "/ask   ",
            "/ask opus",
            "/ask sol   \n",
        ] {
            do {
                _ = try parseAsk(eventName: "issue_comment", commentBody: invalid)
                throw TestFailure(description: "Should reject invalid /ask comment '\(invalid)'")
            } catch is ReviewLoopError {}
        }

        try expect(
            parseAsk(
                eventName: "workflow_dispatch",
                dispatchModel: "auto",
                dispatchInstructions: "Update the docs",
                dispatchPRNumber: "31",
                dispatchDryRun: "true"
            )
                == AskPlan(
                    matched: true,
                    modelOverride: nil,
                    prNumber: 31,
                    instructions: "Update the docs",
                    dryRun: true
                ),
            "workflow_dispatch auto /ask should parse"
        )
        try expect(
            parseAsk(
                eventName: "workflow_dispatch",
                dispatchModel: "opus",
                dispatchInstructions: "Audit memory usage",
                dispatchPRNumber: "31",
                dispatchDryRun: "false"
            )
                == AskPlan(
                    matched: true,
                    modelOverride: .opus,
                    prNumber: 31,
                    instructions: "Audit memory usage",
                    dryRun: false
                ),
            "workflow_dispatch explicit model /ask should parse"
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
                "/Users/tester/.gemini/antigravity/worktrees/d5426dc2-8684-4b55-944e-7a28e4cfe969/subagent-Router-self-7d334d49",
                homeDirectory: home)
                == .antigravity,
            "Antigravity subagent worktree path should classify"
        )
        try expect(
            classifyWorktreePath(
                "/Users/tester/.gemini/antigravity/worktrees/other-repo/my_branch",
                homeDirectory: home)
                == .unknown,
            "Other Antigravity repo path should classify as unknown"
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

        let resolvedAgyWT = agyWT.standardizedFileURL.resolvingSymlinksInPath().path
        let opusAgyDir = root.appending(path: "agy-opus", directoryHint: .isDirectory)
        try createAgyConversationDB(
            at: opusAgyDir,
            rows: [
                (
                    convID: "conv-older", worktree: resolvedAgyWT,
                    modifiedTime: "2026-11-20T01:00:00Z", model: "gemini-4-neon-high"
                ),
                (
                    convID: "conv-newer", worktree: resolvedAgyWT,
                    modifiedTime: "2026-11-20T02:00:00Z", model: "claude-opus-5-5-high"
                ),
            ]
        )

        let hydrogenAgyDir = root.appending(path: "agy-hydrogen", directoryHint: .isDirectory)
        try createAgyConversationDB(
            at: hydrogenAgyDir,
            rows: [
                (
                    convID: "conv-h", worktree: resolvedAgyWT,
                    modifiedTime: "2026-11-20T03:00:00Z", model: "gemini-4-hydrogen-high"
                )
            ]
        )

        let emptyAgyDir = root.appending(path: "agy-empty", directoryHint: .isDirectory)

        // 1. Codex detached worktree discovery -> sol author, neon default reviewer, all = [neon, opus].
        let codexRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "codex/detached-pr",
            headSHA: baseSHA,
            action: .review,
            superDBPath: dbPath,
            agyDirectory: emptyAgyDir.path,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            codexRes.status == "ok",
            "Codex detached worktree should succeed: \(codexRes.error ?? "")")
        try expect(codexRes.author == AgentModel.sol.profile, "Expected sol author")
        try expect(
            codexRes.reviewers == [AgentModel.neon.profile], "Expected neon default reviewer")

        let codexAllRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "codex/detached-pr",
            headSHA: baseSHA,
            action: .review,
            reviewAll: true,
            superDBPath: dbPath,
            agyDirectory: emptyAgyDir.path,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            codexAllRes.status == "ok"
                && codexAllRes.reviewers == [AgentModel.neon.profile, AgentModel.opus.profile],
            "Expected /review all on sol PR to run [neon, opus]"
        )

        // 2. Antigravity worktree auto-detects Opus, Hydrogen, or falls back to Neon.
        let agyOpusRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "feature_one",
            headSHA: agySHA,
            action: .review,
            superDBPath: dbPath,
            agyDirectory: opusAgyDir.path,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(agyOpusRes.status == "ok", "Antigravity Opus worktree should succeed")
        try expect(agyOpusRes.author == AgentModel.opus.profile, "Expected opus author")
        try expect(
            agyOpusRes.reviewers == [AgentModel.sol.profile],
            "Expected sol default reviewer for opus PR")

        let agyOpusAllRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "feature_one",
            headSHA: agySHA,
            action: .review,
            reviewAll: true,
            superDBPath: dbPath,
            agyDirectory: opusAgyDir.path,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            agyOpusAllRes.reviewers == [AgentModel.sol.profile, AgentModel.neon.profile],
            "Expected /review all on opus PR to run [sol, neon]"
        )

        let agyHydrogenAllRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "feature_one",
            headSHA: agySHA,
            action: .review,
            reviewAll: true,
            superDBPath: dbPath,
            agyDirectory: hydrogenAgyDir.path,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            agyHydrogenAllRes.author == AgentModel.hydrogen.profile
                && agyHydrogenAllRes.reviewers == [AgentModel.sol.profile, AgentModel.opus.profile],
            "Expected /review all on hydrogen PR to run [sol, opus]"
        )

        let agyFallbackRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "feature_one",
            headSHA: agySHA,
            action: .review,
            superDBPath: dbPath,
            agyDirectory: emptyAgyDir.path,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            agyFallbackRes.status == "ok" && agyFallbackRes.author == AgentModel.neon.profile,
            "Missing Antigravity DB should fall back cleanly to neon"
        )

        // 3. Explicit /address override overrides detected author.
        let addressOverrideRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "feature_one",
            headSHA: agySHA,
            action: .address,
            authorOverride: .opus,
            superDBPath: dbPath,
            agyDirectory: emptyAgyDir.path,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            addressOverrideRes.status == "ok"
                && addressOverrideRes.author == AgentModel.opus.profile,
            "/address opus should override detected author"
        )

        // 4. super.engineering with multiple providers picks latest (codex -> sol) and adds note.
        let superRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "codex/super-branch",
            headSHA: superSHA,
            action: .review,
            superDBPath: dbPath,
            agyDirectory: emptyAgyDir.path,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(superRes.status == "ok", "super.engineering codex worktree should succeed")
        try expect(superRes.author == AgentModel.sol.profile, "Expected sol author from super DB")
        try expect(
            superRes.notes.contains(where: { $0.contains("Multiple super.engineering providers") }),
            "Expected multiple-provider log note"
        )

        // 5. Non-codex super.engineering provider stops when no override.
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
            superDBPath: claudeDBPath,
            agyDirectory: emptyAgyDir.path,
            homeDirectory: home.path,
            requireClean: false
        )
        try expect(claudeRes.status == "error", "Non-codex super.engineering provider must stop")

        // 6. /review <reviewer> override falls back to default reviewer for unknown path.
        let overrideRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "main",
            headSHA: baseSHA,
            action: .review,
            reviewerOverride: [.sol],
            superDBPath: dbPath,
            agyDirectory: emptyAgyDir.path,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(overrideRes.status == "ok", "Override should allow unknown path")
        try expect(overrideRes.reviewers == [AgentModel.sol.profile], "Override reviewer should be sol")
        try expect(
            overrideRes.author == AgentModel.neon.profile,
            "Override fallback author should be neon")

        // 7. --require-clean catches stale HEAD and dirty working tree.
        let staleRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "feature_one",
            headSHA: baseSHA,
            action: .address,
            superDBPath: dbPath,
            agyDirectory: emptyAgyDir.path,
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
            superDBPath: dbPath,
            agyDirectory: emptyAgyDir.path,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            dirtyRes.status == "error" && (dirtyRes.error ?? "").contains("uncommitted"),
            "Dirty worktree must fail"
        )

        // 8. /ask discovery supports both auto-detected author and explicit cross-model override.
        let askAutoRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "feature_one",
            headSHA: agySHA,
            action: .ask,
            targetModel: nil,
            superDBPath: dbPath,
            agyDirectory: opusAgyDir.path,
            homeDirectory: home.path,
            requireClean: false
        )
        try expect(
            askAutoRes.status == "ok" && askAutoRes.author == AgentModel.opus.profile,
            "Bare /ask should auto-detect opus author from Antigravity DB"
        )

        let askCrossRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "codex/detached-pr",
            headSHA: baseSHA,
            action: .ask,
            targetModel: .opus,
            superDBPath: dbPath,
            agyDirectory: emptyAgyDir.path,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            askCrossRes.status == "ok"
                && askCrossRes.author == AgentModel.opus.profile
                && askCrossRes.worktreePath != nil,
            "/ask opus should run in a Codex worktree"
        )

        let askSuperRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "codex/super-branch",
            headSHA: superSHA,
            action: .ask,
            targetModel: .sol,
            superDBPath: claudeDBPath,
            agyDirectory: emptyAgyDir.path,
            homeDirectory: home.path,
            requireClean: true
        )
        try expect(
            askSuperRes.status == "ok" && askSuperRes.author == AgentModel.sol.profile,
            "/ask with explicit model should work on super.engineering worktree regardless of DB provider"
        )

        let askMissingRes = discoverLoopContext(
            canonicalRepoPath: canonical.path,
            branch: "missing-branch",
            headSHA: "deadbeef",
            action: .ask,
            targetModel: .sol,
            superDBPath: dbPath,
            agyDirectory: emptyAgyDir.path,
            homeDirectory: home.path,
            requireClean: false
        )
        try expect(
            askMissingRes.status == "error",
            "/ask without a local worktree must fail even when requireClean is false"
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

        let createWhenNoID = try resolveCheckRunMode(
            checkRunID: nil,
            status: .queued,
            recreateIfCompleted: false,
            existingStatus: {
                throw TestFailure(description: "Must not query status without checkRunID")
            }
        )
        try expect(createWhenNoID == .create, "Missing checkRunID must create")

        let updateQueued = try resolveCheckRunMode(
            checkRunID: "123",
            status: .inProgress,
            recreateIfCompleted: true,
            existingStatus: { .queued }
        )
        try expect(updateQueued == .update("123"), "Queued check run must update in place")

        let recreateCompleted = try resolveCheckRunMode(
            checkRunID: "123",
            status: .inProgress,
            recreateIfCompleted: true,
            existingStatus: { .completed }
        )
        try expect(
            recreateCompleted == .create,
            "Completed check run must create a fresh check run when reopening")

        let updateCompletedWithoutRecreate = try resolveCheckRunMode(
            checkRunID: "123",
            status: .completed,
            recreateIfCompleted: true,
            existingStatus: {
                throw TestFailure(description: "Completing a check run must not query status")
            }
        )
        try expect(
            updateCompletedWithoutRecreate == .update("123"),
            "Completed target status must update in place")
    }

    private func testMonitorRecord(in root: URL) throws {
        let monitorDir = root.appending(path: "monitor", directoryHint: .isDirectory)

        try recordMonitorState(
            monitorDirectory: monitorDir.path,
            runID: "999",
            kind: "review-loop",
            phase: "review-sol",
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
            phase: "review-sol",
            botLogin: "clinical-codex[bot]",
            model: "gpt-6.1-sol",
            effort: "high",
            worktreePath: "/tmp/pr",
            prompt: "Review PR #33",
            streamFile: monitorDir.appending(path: "runs/999/review-sol.jsonl").path,
            status: .running,
            timestamp: "2026-11-19T08:01:00Z"
        )

        try recordMonitorState(
            monitorDirectory: monitorDir.path,
            runID: "999",
            phase: "review-sol",
            status: .completed,
            conclusion: "success",
            timestamp: "2026-11-19T08:03:00Z"
        )

        let runData = try Data(contentsOf: monitorDir.appending(path: "runs/999/run.json"))
        let runRecord = try JSONDecoder().decode(MonitorRunRecord.self, from: runData)
        try expect(runRecord.prNumber == 33, "Expected prNumber preserved")
        try expect(runRecord.createdAt == "2026-11-19T08:00:00Z", "Expected createdAt preserved")
        try expect(runRecord.updatedAt == "2026-11-19T08:03:00Z", "Expected updatedAt updated")

        let phaseData = try Data(contentsOf: monitorDir.appending(path: "runs/999/review-sol.json"))
        let phaseRecord = try JSONDecoder().decode(MonitorPhaseRecord.self, from: phaseData)
        try expect(phaseRecord.phase == "review-sol", "Expected phase review-sol")
        try expect(phaseRecord.harness == .codex, "Expected harness preserved across updates")
        try expect(phaseRecord.prompt == "Review PR #33", "Expected prompt preserved across updates")
        try expect(phaseRecord.startedAt == "2026-11-19T08:01:00Z", "Expected startedAt preserved")
        try expect(phaseRecord.completedAt == "2026-11-19T08:03:00Z", "Expected completedAt set")
        try expect(phaseRecord.conclusion == "success", "Expected conclusion recorded")

        for legacyPhase in ["review", "bot", "review-unknown"] {
            do {
                try recordMonitorState(
                    monitorDirectory: monitorDir.path,
                    runID: "999",
                    phase: legacyPhase,
                    status: .queued
                )
                throw TestFailure(description: "Should reject phase '\(legacyPhase)'")
            } catch is ReviewLoopError {}
        }
    }

    private func testCommentReactionEndpoint() throws {
        try expect(
            commentReactionEndpoint(
                repo: "owner/repo", eventName: "issue_comment", commentID: "12345")
                == "repos/owner/repo/issues/comments/12345/reactions",
            "issue_comment should use issues comments reactions endpoint"
        )
        try expect(
            commentReactionEndpoint(
                repo: "owner/repo", eventName: "pull_request_review_comment", commentID: "67890")
                == "repos/owner/repo/pulls/comments/67890/reactions",
            "pull_request_review_comment should use pulls comments reactions endpoint"
        )
        try expect(
            commentReactionEndpoint(
                repo: "owner/repo", eventName: "pull_request_review", commentID: "111") == nil,
            "pull_request_review has no reactions endpoint"
        )
        try expect(
            commentReactionEndpoint(
                repo: "owner/repo", eventName: "workflow_dispatch", commentID: "111") == nil,
            "workflow_dispatch has no reactions endpoint"
        )
        try expect(
            commentReactionEndpoint(
                repo: "owner/repo", eventName: "issue_comment", commentID: "  ") == nil,
            "Empty comment ID should return nil"
        )
    }

    private func testUnresolvedReviewThreads() throws {
        let emptyJSON = """
            {
              "data": {
                "repository": {
                  "pullRequest": {
                    "reviewThreads": {
                      "pageInfo": { "hasNextPage": false, "endCursor": null },
                      "nodes": []
                    }
                  }
                }
              }
            }
            """
        let emptyCount = try countUnresolvedReviewThreads(
            repo: "vickychijwani/clinical-swift",
            prNumber: 39,
            fetchPage: { _, _, _, _ in emptyJSON }
        )
        try expect(emptyCount == 0, "Empty reviewThreads should yield 0")

        let page1 = """
            {
              "data": {
                "repository": {
                  "pullRequest": {
                    "reviewThreads": {
                      "pageInfo": { "hasNextPage": true, "endCursor": "cursor-1" },
                      "nodes": [
                        {
                          "isResolved": true,
                          "comments": {
                            "nodes": [
                              { "author": { "__typename": "Bot", "login": "clinical-codex" } }
                            ]
                          }
                        },
                        {
                          "isResolved": false,
                          "comments": {
                            "nodes": [
                              { "author": { "__typename": "Bot", "login": "clinical-codex" } }
                            ]
                          }
                        },
                        {
                          "isResolved": false,
                          "comments": {
                            "nodes": [
                              { "author": { "__typename": "User", "login": "clinical-codex" } }
                            ]
                          }
                        },
                        {
                          "isResolved": false,
                          "comments": {
                            "nodes": [
                              { "author": { "__typename": "User", "login": "stranger" } },
                              { "author": null }
                            ]
                          }
                        }
                      ]
                    }
                  }
                }
              }
            }
            """
        let page2 = """
            {
              "data": {
                "repository": {
                  "pullRequest": {
                    "reviewThreads": {
                      "pageInfo": { "hasNextPage": false, "endCursor": "cursor-2" },
                      "nodes": [
                        {
                          "isResolved": false,
                          "comments": {
                            "nodes": [
                              { "author": { "__typename": "Bot", "login": "clinical-antigravity" } }
                            ]
                          }
                        },
                        {
                          "isResolved": false,
                          "comments": {
                            "nodes": [
                              { "author": { "__typename": "User", "login": "VickyChijwani" } }
                            ]
                          }
                        },
                        {
                          "isResolved": false,
                          "comments": {
                            "nodes": [
                              { "author": { "__typename": "User", "login": "stranger" } },
                              { "author": { "__typename": "Bot", "login": "clinical-codex[bot]" } }
                            ]
                          }
                        }
                      ]
                    }
                  }
                }
              }
            }
            """
        var requestedCursors: [String?] = []
        let paginatedCount = try countUnresolvedReviewThreads(
            repo: "vickychijwani/clinical-swift",
            prNumber: 42,
            fetchPage: { owner, name, prNumber, after in
                try expect(owner == "vickychijwani" && name == "clinical-swift", "Repo split mismatch")
                try expect(prNumber == 42, "PR number mismatch")
                requestedCursors.append(after)
                return after == nil ? page1 : page2
            }
        )
        try expect(
            requestedCursors == [nil, "cursor-1"],
            "Expected two GraphQL pages with cursor-1, got \(requestedCursors)"
        )
        // Page 1: 1 (Bot clinical-codex); ignores resolved, User spoof clinical-codex, stranger/null.
        // Page 2: 3 (Bot clinical-antigravity, owner case-insensitive, mixed stranger + trusted bot).
        try expect(
            paginatedCount == 4,
            "Expected 4 trusted unresolved threads across pages, got \(paginatedCount)"
        )

        let errorJSON = """
            { "errors": [{ "message": "API rate limit exceeded" }] }
            """
        var threwGraphQLError = false
        do {
            _ = try parseReviewThreadPage(errorJSON)
        } catch {
            threwGraphQLError = true
        }
        try expect(threwGraphQLError, "GraphQL errors payload must throw")

        let missingPRJSON = """
            { "data": { "repository": { "pullRequest": null } } }
            """
        var threwMissingPR = false
        do {
            _ = try parseReviewThreadPage(missingPRJSON)
        } catch {
            threwMissingPR = true
        }
        try expect(threwMissingPR, "Missing pullRequest payload must throw")

        var threwBadRepo = false
        do {
            _ = try countUnresolvedReviewThreads(
                repo: "not-a-repo",
                prNumber: 1,
                fetchPage: { _, _, _, _ in emptyJSON }
            )
        } catch {
            threwBadRepo = true
        }
        try expect(threwBadRepo, "Invalid repo string must throw")

        let loopJSON = """
            {
              "data": {
                "repository": {
                  "pullRequest": {
                    "reviewThreads": {
                      "pageInfo": { "hasNextPage": true, "endCursor": "same-cursor" },
                      "nodes": []
                    }
                  }
                }
              }
            }
            """
        var threwLoopCursor = false
        do {
            _ = try countUnresolvedReviewThreads(
                repo: "owner/repo",
                prNumber: 1,
                fetchPage: { _, _, _, _ in loopJSON }
            )
        } catch {
            threwLoopCursor = true
        }
        try expect(threwLoopCursor, "Repeated pagination cursor must throw")
    }

    private func runAllTests() {
        let tempRoot = FileManager.default.temporaryDirectory.appending(
            path: "agent-review-loop-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        do {
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            try testParseTrigger()
            try testParseAsk()
            try testWorktreeClassificationAndParsing()
            try testDiscoveryIntegration(in: tempRoot)
            try testCodexSkillsConfig(in: tempRoot)
            try testCheckRunPayload()
            try testCommentReactionEndpoint()
            try testUnresolvedReviewThreads()
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
            cliBinary.path, "parse-trigger", "--event", "issue_comment", "--body",
            "/review sol opus",
        ])
        try expect(
            triggerOut.contains("\"reviewerOverride\":[\"sol\",\"opus\"]"),
            "CLI parse-trigger failed")
        let askOut = try runShell([
            cliBinary.path, "parse-ask", "--event", "issue_comment", "--body",
            "/ask opus fix it",
        ])
        try expect(
            askOut.contains("\"matched\":true")
                && askOut.contains("\"modelOverride\":\"opus\""),
            "CLI parse-ask failed"
        )
        let monitorDir = tempDir.appending(path: "cli-monitor")
        _ = try runShell([
            cliBinary.path, "monitor-record",
            "--monitor-dir", monitorDir.path,
            "--run-id", "42",
            "--phase", "review-opus",
            "--harness", "antigravity",
            "--model", "claude-opus-5-5",
            "--effort", "high",
            "--status", "queued",
        ])
        try expect(
            FileManager.default.fileExists(
                atPath: monitorDir.appending(path: "runs/42/review-opus.json").path),
            "CLI monitor-record review-opus failed"
        )
        _ = try runShell([
            cliBinary.path, "monitor-record",
            "--monitor-dir", monitorDir.path,
            "--run-id", "43",
            "--phase", "ask",
            "--harness", "antigravity",
            "--model", "claude-opus-5-5",
            "--effort", "high",
            "--status", "queued",
        ])
        try expect(
            FileManager.default.fileExists(
                atPath: monitorDir.appending(path: "runs/43/ask.json").path),
            "CLI monitor-record ask failed"
        )
        _ = try runShell([
            cliBinary.path, "react",
            "--repo", "owner/repo",
            "--event", "workflow_dispatch",
            "--comment-id", "",
            "--content", "eyes",
        ])
        print("PASS agent review loop CLI compilation and smoke check")
    } catch {
        FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
        exit(1)
    }
#endif
