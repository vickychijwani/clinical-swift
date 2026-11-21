import Foundation
import SQLite3

struct ReviewLoopError: Error, CustomStringConvertible {
    let description: String
}

enum Harness: String, Codable, Equatable {
    case codex
    case antigravity

    var botLogin: String {
        switch self {
        case .codex: "clinical-codex[bot]"
        case .antigravity: "clinical-antigravity[bot]"
        }
    }
}

enum AgentModel: String, Codable, Equatable, Hashable, CaseIterable {
    case sol
    case neon
    case hydrogen
    case opus

    var harness: Harness {
        switch self {
        case .sol: .codex
        case .neon, .hydrogen, .opus: .antigravity
        }
    }

    var cliModel: String {
        switch self {
        case .sol: "gpt-6.1-sol"
        case .neon: "gemini-4-neon"
        case .hydrogen: "gemini-4-hydrogen"
        case .opus: "claude-opus-5-5"
        }
    }

    var effort: String { "high" }

    var displayName: String {
        switch self {
        case .sol: "GPT-6.1 Sol"
        case .neon: "Gemini 4 Neon"
        case .hydrogen: "Gemini 4 Hydrogen"
        case .opus: "Claude Opus 5.5"
        }
    }

    var botLogin: String { harness.botLogin }

    var defaultReviewer: AgentModel {
        switch self {
        case .sol: .neon
        case .neon, .hydrogen, .opus: .sol
        }
    }

    var allReviewers: [AgentModel] {
        switch self {
        case .sol: [.neon, .opus]
        case .neon, .hydrogen: [.sol, .opus]
        case .opus: [.sol, .neon]
        }
    }

    var profile: AgentProfile {
        AgentProfile(
            id: rawValue,
            harness: harness,
            botLogin: botLogin,
            cliModel: cliModel,
            effort: effort,
            displayName: displayName
        )
    }

    static func fromTranscriptModel(_ raw: String) -> AgentModel? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("claude-opus") {
            return .opus
        }
        if lower.hasPrefix("gemini-4-hydrogen") {
            return .hydrogen
        }
        if lower.hasPrefix("gemini-4-neon") {
            return .neon
        }
        if lower.hasPrefix("gpt-6.1-sol") {
            return .sol
        }
        return nil
    }
}

struct AgentProfile: Codable, Equatable {
    let id: String
    let harness: Harness
    let botLogin: String
    let cliModel: String
    let effort: String
    let displayName: String
}

enum LoopAction: String, Codable, Equatable {
    case review
    case address
    case ask
}

struct TriggerPlan: Codable, Equatable {
    let action: LoopAction
    let prNumber: Int?
    let reviewerOverride: [AgentModel]?
    let reviewAll: Bool
    let authorOverride: AgentModel?
    let dryRun: Bool
}

struct AskPlan: Codable, Equatable {
    let matched: Bool
    let modelOverride: AgentModel?
    let prNumber: Int?
    let instructions: String?
    let dryRun: Bool
}

struct WorktreeEntry: Equatable {
    let path: String
    let head: String
    let branch: String?
    let isDetached: Bool
}

enum WorktreeKind: Equatable {
    case codex
    case antigravity
    case superEngineering
    case unknown
}

struct DiscoveryOutput: Codable, Equatable {
    let status: String
    let worktreePath: String?
    let author: AgentProfile?
    let reviewers: [AgentProfile]
    let notes: [String]
    let error: String?
}

private func normalizePath(_ path: String, resolveSymlinks: Bool = true) -> String {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let resolved = resolveSymlinks ? url.resolvingSymlinksInPath() : url
    var result = resolved.path
    while result.count > 1 && result.hasSuffix("/") {
        result.removeLast()
    }
    return result
}

private func runProcess(
    executable: String = "/usr/bin/env",
    arguments: [String],
    workingDirectory: String? = nil,
    stdinData: Data? = nil
) throws -> (exitCode: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let workingDirectory {
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
    }
    let stdinPipe: Pipe?
    if let stdinData {
        let pipe = Pipe()
        process.standardInput = pipe
        stdinPipe = pipe
        _ = stdinData
    } else {
        process.standardInput = FileHandle.nullDevice
        stdinPipe = nil
    }
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    try process.run()
    if let stdinPipe, let stdinData {
        stdinPipe.fileHandleForWriting.write(stdinData)
        try? stdinPipe.fileHandleForWriting.close()
    }
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (
        process.terminationStatus,
        String(decoding: stdoutData, as: UTF8.self),
        String(decoding: stderrData, as: UTF8.self)
    )
}

private func git(_ repoPath: String, _ arguments: [String]) throws -> String {
    let result = try runProcess(arguments: ["git", "-C", repoPath] + arguments)
    guard result.exitCode == 0 else {
        let details = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        throw ReviewLoopError(
            description: "git \(arguments.joined(separator: " ")) failed: \(details)")
    }
    return result.stdout
}

private func parseReviewerList(_ tokens: [String]) throws -> (
    models: [AgentModel]?, reviewAll: Bool
) {
    if tokens.isEmpty {
        return (nil, false)
    }
    if tokens.count == 1 && tokens[0] == "all" {
        return (nil, true)
    }
    var seen = Set<AgentModel>()
    var models: [AgentModel] = []
    for token in tokens {
        guard let model = AgentModel(rawValue: token) else {
            throw ReviewLoopError(
                description:
                    "Invalid /review command. Use `/review`, `/review all`, or `/review <sol|neon|hydrogen|opus> [...]`."
            )
        }
        if seen.insert(model).inserted {
            models.append(model)
        }
    }
    return (models, false)
}

/// Parses `/review [all | sol|neon|hydrogen|opus ...]` or `/address [sol|neon|hydrogen|opus]` PR comments and workflow_dispatch inputs.
func parseTrigger(
    eventName: String,
    commentBody: String? = nil,
    dispatchAction: String? = nil,
    dispatchReviewer: String? = nil,
    dispatchAuthor: String? = nil,
    dispatchPRNumber: String? = nil,
    dispatchDryRun: String? = nil
) throws -> TriggerPlan {
    switch eventName {
    case "issue_comment":
        let raw = (commentBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let command = tokens.first else {
            throw ReviewLoopError(description: "Empty PR comment.")
        }
        switch command {
        case "/review":
            let args = Array(tokens.dropFirst()).map { $0.lowercased() }
            let (models, reviewAll) = try parseReviewerList(args)
            return TriggerPlan(
                action: .review,
                prNumber: nil,
                reviewerOverride: models,
                reviewAll: reviewAll,
                authorOverride: nil,
                dryRun: false
            )
        case "/address":
            if tokens.count == 1 {
                return TriggerPlan(
                    action: .address,
                    prNumber: nil,
                    reviewerOverride: nil,
                    reviewAll: false,
                    authorOverride: nil,
                    dryRun: false
                )
            }
            guard tokens.count == 2, let model = AgentModel(rawValue: tokens[1].lowercased()) else {
                throw ReviewLoopError(
                    description:
                        "Invalid /address command. Use `/address` or `/address <sol|neon|hydrogen|opus>`."
                )
            }
            return TriggerPlan(
                action: .address,
                prNumber: nil,
                reviewerOverride: nil,
                reviewAll: false,
                authorOverride: model,
                dryRun: false
            )
        default:
            throw ReviewLoopError(description: "Unsupported trigger command: \(command)")
        }

    case "workflow_dispatch":
        guard let prText = dispatchPRNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
            let prNumber = Int(prText), prNumber > 0
        else {
            throw ReviewLoopError(description: "Invalid workflow_dispatch pr_number.")
        }
        guard let actionText = dispatchAction?.trimmingCharacters(in: .whitespacesAndNewlines),
            let action = LoopAction(rawValue: actionText),
            action == .review || action == .address
        else {
            throw ReviewLoopError(
                description: "Invalid workflow_dispatch action. Use `review` or `address`.")
        }
        let reviewerText = (dispatchReviewer ?? "auto").trimmingCharacters(
            in: .whitespacesAndNewlines)
        let reviewerOverride: [AgentModel]?
        let reviewAll: Bool
        if reviewerText.isEmpty || reviewerText == "auto" {
            reviewerOverride = nil
            reviewAll = false
        } else if action == .review {
            let tokens =
                reviewerText
                .split(whereSeparator: { $0.isWhitespace || $0 == "," })
                .map { String($0).lowercased() }
            do {
                let parsed = try parseReviewerList(tokens)
                reviewerOverride = parsed.models
                reviewAll = parsed.reviewAll
            } catch {
                throw ReviewLoopError(
                    description:
                        "Invalid reviewer option '\(reviewerText)' for action '\(action.rawValue)'."
                )
            }
        } else {
            throw ReviewLoopError(
                description:
                    "Invalid reviewer option '\(reviewerText)' for action '\(action.rawValue)'.")
        }

        let authorText = (dispatchAuthor ?? "auto").trimmingCharacters(in: .whitespacesAndNewlines)
        let authorOverride: AgentModel?
        if authorText.isEmpty || authorText == "auto" {
            authorOverride = nil
        } else if let parsed = AgentModel(rawValue: authorText.lowercased()) {
            authorOverride = parsed
        } else {
            throw ReviewLoopError(
                description:
                    "Invalid author option '\(authorText)'. Use `auto`, `sol`, `neon`, `hydrogen`, or `opus`."
            )
        }

        let dryRun =
            (dispatchDryRun ?? "false").trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        return TriggerPlan(
            action: action,
            prNumber: prNumber,
            reviewerOverride: reviewerOverride,
            reviewAll: reviewAll,
            authorOverride: authorOverride,
            dryRun: dryRun
        )

    default:
        throw ReviewLoopError(description: "Unsupported event: \(eventName)")
    }
}

/// Parses `/ask [sol|neon|hydrogen|opus] <instructions>` PR comments and workflow_dispatch inputs.
func parseAsk(
    eventName: String,
    commentBody: String? = nil,
    dispatchModel: String? = nil,
    dispatchInstructions: String? = nil,
    dispatchPRNumber: String? = nil,
    dispatchDryRun: String? = nil
) throws -> AskPlan {
    switch eventName {
    case "issue_comment", "pull_request_review_comment", "pull_request_review":
        let raw = (commentBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return AskPlan(
                matched: false, modelOverride: nil, prNumber: nil, instructions: nil, dryRun: false)
        }

        let firstTokenEnd = raw.firstIndex(where: \.isWhitespace) ?? raw.endIndex
        guard raw[..<firstTokenEnd] == "/ask" else {
            return AskPlan(
                matched: false, modelOverride: nil, prNumber: nil, instructions: nil, dryRun: false)
        }

        let afterCommand = raw[firstTokenEnd...].drop(while: \.isWhitespace)
        guard !afterCommand.isEmpty else {
            throw ReviewLoopError(description: "Please include instructions after /ask.")
        }

        let nextTokenEnd = afterCommand.firstIndex(where: \.isWhitespace) ?? afterCommand.endIndex
        let candidate = String(afterCommand[..<nextTokenEnd]).lowercased()
        if let model = AgentModel(rawValue: candidate) {
            let instructions = String(afterCommand[nextTokenEnd...].drop(while: \.isWhitespace))
            guard !instructions.isEmpty else {
                throw ReviewLoopError(
                    description: "Please include instructions after /ask \(model.rawValue).")
            }
            return AskPlan(
                matched: true,
                modelOverride: model,
                prNumber: nil,
                instructions: instructions,
                dryRun: false
            )
        }

        return AskPlan(
            matched: true,
            modelOverride: nil,
            prNumber: nil,
            instructions: String(afterCommand),
            dryRun: false
        )

    case "workflow_dispatch":
        guard let prText = dispatchPRNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
            let prNumber = Int(prText), prNumber > 0
        else {
            throw ReviewLoopError(description: "Invalid workflow_dispatch pr_number.")
        }
        let modelText = (dispatchModel ?? "auto").trimmingCharacters(in: .whitespacesAndNewlines)
        let modelOverride: AgentModel?
        if modelText.isEmpty || modelText == "auto" {
            modelOverride = nil
        } else if let parsed = AgentModel(rawValue: modelText.lowercased()) {
            modelOverride = parsed
        } else {
            throw ReviewLoopError(
                description:
                    "Invalid workflow_dispatch model. Use `auto`, `sol`, `neon`, `hydrogen`, or `opus`."
            )
        }
        let instructions = (dispatchInstructions ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !instructions.isEmpty else {
            throw ReviewLoopError(
                description: "Invalid workflow_dispatch instructions: cannot be empty.")
        }
        let dryRun =
            (dispatchDryRun ?? "false").trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        return AskPlan(
            matched: true,
            modelOverride: modelOverride,
            prNumber: prNumber,
            instructions: instructions,
            dryRun: dryRun
        )

    default:
        throw ReviewLoopError(description: "Unsupported event: \(eventName)")
    }
}

/// Parses `git worktree list --porcelain` output into structured entries.
func parseWorktreeList(_ output: String) -> [WorktreeEntry] {
    var entries: [WorktreeEntry] = []
    var currentPath: String?
    var currentHead: String?
    var currentBranch: String?
    var currentDetached = false

    func flush() {
        if let path = currentPath, let head = currentHead {
            entries.append(
                WorktreeEntry(
                    path: path, head: head, branch: currentBranch, isDetached: currentDetached)
            )
        }
        currentPath = nil
        currentHead = nil
        currentBranch = nil
        currentDetached = false
    }

    for rawLine in output.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty {
            flush()
        } else if line.hasPrefix("worktree ") {
            currentPath = String(line.dropFirst("worktree ".count))
        } else if line.hasPrefix("HEAD ") {
            currentHead = String(line.dropFirst("HEAD ".count))
        } else if line.hasPrefix("branch ") {
            currentBranch = String(line.dropFirst("branch ".count))
        } else if line == "detached" {
            currentDetached = true
        }
    }
    flush()
    return entries
}

/// Classifies a worktree path against the three supported agent worktree layouts.
func classifyWorktreePath(_ path: String, homeDirectory: String) -> WorktreeKind {
    let normalizedHome = normalizePath(homeDirectory, resolveSymlinks: false)
    let normalizedPath = normalizePath(path, resolveSymlinks: false)
    let prefix = normalizedHome == "/" ? "/" : normalizedHome + "/"
    guard normalizedPath.hasPrefix(prefix) else { return .unknown }

    let relative = String(normalizedPath.dropFirst(prefix.count))
    let components = relative.split(separator: "/").map(String.init)
    // Expected layouts:
    // - .codex/worktrees/<id>/clinical-swift
    // - .gemini/antigravity/worktrees/clinical-swift/<name>
    // - .gemini/antigravity/worktrees/<conversation-id>/<name>
    // - .super.engineering/worktrees/clinical-swift/<name>
    if components.count == 4 && components[0] == ".codex" && components[1] == "worktrees"
        && components[3] == "clinical-swift"
    {
        return .codex
    }
    if components.count == 5 && components[0] == ".gemini" && components[1] == "antigravity"
        && components[2] == "worktrees"
        && (components[3] == "clinical-swift" || UUID(uuidString: components[3]) != nil)
    {
        return .antigravity
    }
    if components.count == 4 && components[0] == ".super.engineering"
        && components[1] == "worktrees" && components[2] == "clinical-swift"
    {
        return .superEngineering
    }
    return .unknown
}

/// Locates the unique PR worktree by branch first, then detached HEAD in known author roots.
func locateWorktree(
    entries: [WorktreeEntry],
    branch: String,
    headSHA: String,
    homeDirectory: String
) throws -> WorktreeEntry? {
    let targetRef = "refs/heads/\(branch)"
    let branchMatches = entries.filter { $0.branch == targetRef }
    if let match = branchMatches.first {
        return match
    }

    let detachedMatches = entries.filter { entry in
        guard entry.isDetached && entry.head == headSHA else { return false }
        let kind = classifyWorktreePath(entry.path, homeDirectory: homeDirectory)
        return kind != .unknown
    }
    if detachedMatches.count > 1 {
        let paths = detachedMatches.map(\.path).joined(separator: ", ")
        throw ReviewLoopError(
            description: "Multiple detached author worktrees match PR head \(headSHA): \(paths)."
        )
    }
    return detachedMatches.first
}

/// Reads the provider_key history for a super.engineering worktree, read-only.
func querySuperEngineeringProviders(databasePath: String, worktreePaths: [String]) throws
    -> [String]
{
    guard FileManager.default.fileExists(atPath: databasePath) else {
        throw ReviewLoopError(
            description: "super.engineering database not found at \(databasePath).")
    }

    var db: OpaquePointer?
    guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
        let detail = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
        if let db { sqlite3_close(db) }
        throw ReviewLoopError(description: "Cannot open super.engineering database: \(detail)")
    }
    defer { sqlite3_close(db) }

    let uniquePaths = Array(Set(worktreePaths))
    let placeholders = uniquePaths.map { _ in "?" }.joined(separator: ", ")
    let sql = """
        SELECT provider_key
        FROM conversations
        WHERE json_extract(metadata, '$.worktree_path') IN (\(placeholders))
        ORDER BY updated_at DESC, created_at DESC;
        """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        let detail = String(cString: sqlite3_errmsg(db))
        throw ReviewLoopError(
            description: "Cannot query super.engineering conversations: \(detail)")
    }
    defer { sqlite3_finalize(statement) }

    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, path) in uniquePaths.enumerated() {
        sqlite3_bind_text(statement, Int32(index + 1), path, -1, transient)
    }

    var providers: [String] = []
    while true {
        let step = sqlite3_step(statement)
        if step == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                providers.append(String(cString: cString))
            }
        } else if step == SQLITE_DONE {
            break
        } else {
            let detail = String(cString: sqlite3_errmsg(db))
            throw ReviewLoopError(
                description: "Failed reading super.engineering conversations: \(detail)")
        }
    }
    return providers
}

/// Reads matching Antigravity conversation IDs for a worktree path, newest first.
func queryAntigravityConversations(databasePath: String, worktreePaths: [String]) throws -> [String]
{
    guard FileManager.default.fileExists(atPath: databasePath) else {
        return []
    }

    var db: OpaquePointer?
    guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
        let detail = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
        if let db { sqlite3_close(db) }
        throw ReviewLoopError(
            description: "Cannot open Antigravity conversation database: \(detail)")
    }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 2000)

    let targetPaths = Set(
        worktreePaths.flatMap { [normalizePath($0, resolveSymlinks: false), normalizePath($0, resolveSymlinks: true)] }
    )
    let sql = """
        SELECT conversation_id, workspace_uris
        FROM conversation_summaries
        ORDER BY last_modified_time DESC;
        """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        let detail = String(cString: sqlite3_errmsg(db))
        throw ReviewLoopError(
            description: "Cannot query Antigravity conversations: \(detail)")
    }
    defer { sqlite3_finalize(statement) }

    var matches: [String] = []
    while true {
        let step = sqlite3_step(statement)
        if step == SQLITE_ROW {
            guard let idCString = sqlite3_column_text(statement, 0),
                let urisCString = sqlite3_column_text(statement, 1)
            else { continue }
            let convID = String(cString: idCString)
            let urisRaw = String(cString: urisCString)
            guard let data = urisRaw.data(using: .utf8),
                let uris = try? JSONDecoder().decode([String].self, from: data)
            else { continue }
            let matched = uris.contains { uri in
                guard let url = URL(string: uri), url.isFileURL else { return false }
                let rawPath = normalizePath(url.path, resolveSymlinks: false)
                let resolvedPath = normalizePath(url.path, resolveSymlinks: true)
                return targetPaths.contains(rawPath) || targetPaths.contains(resolvedPath)
            }
            if matched {
                matches.append(convID)
            }
        } else if step == SQLITE_DONE {
            break
        } else {
            let detail = String(cString: sqlite3_errmsg(db))
            throw ReviewLoopError(
                description: "Failed reading Antigravity conversations: \(detail)")
        }
    }
    return matches
}

/// Reads the latest recognized Antigravity model from a conversation transcript.
func readLatestAntigravityModel(transcriptPath: String) -> AgentModel? {
    guard let content = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else {
        return nil
    }
    for rawLine in content.split(whereSeparator: \.isNewline).reversed() {
        guard let data = String(rawLine).data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (obj["type"] as? String) == "PLANNER_RESPONSE",
            let modelText = obj["model"] as? String,
            let model = AgentModel.fromTranscriptModel(modelText),
            model.harness == .antigravity
        else { continue }
        return model
    }
    return nil
}

/// Detects whether an Antigravity worktree was authored by neon, hydrogen, or opus, falling back to neon.
func detectAntigravityAuthorModel(
    worktreePath: String,
    agyDirectory: String
) -> (model: AgentModel, notes: [String]) {
    let dbPath = normalizePath("\(agyDirectory)/conversation_summaries.db", resolveSymlinks: false)
    let candidates = [
        normalizePath(worktreePath, resolveSymlinks: false),
        normalizePath(worktreePath, resolveSymlinks: true),
    ]
    do {
        let conversationIDs = try queryAntigravityConversations(
            databasePath: dbPath, worktreePaths: candidates)
        for convID in conversationIDs.prefix(5) {
            let transcriptPath =
                "\(agyDirectory)/brain/\(convID)/.system_generated/logs/transcript.jsonl"
            if let model = readLatestAntigravityModel(transcriptPath: transcriptPath) {
                return (model, [])
            }
        }
        return (
            .neon,
            [
                "No recognized Antigravity model found in local transcripts for \(worktreePath); defaulting to neon."
            ]
        )
    } catch {
        return (
            .neon,
            [
                "Could not read Antigravity conversation history (\(error)); defaulting to neon."
            ]
        )
    }
}

private func resolveAuthorModel(
    worktreePath: String,
    homeDirectory: String,
    superDBPath: String,
    agyDirectory: String
) -> (model: AgentModel?, notes: [String], reason: String?) {
    switch classifyWorktreePath(worktreePath, homeDirectory: homeDirectory) {
    case .codex:
        return (.sol, [], nil)
    case .antigravity:
        let detected = detectAntigravityAuthorModel(
            worktreePath: worktreePath, agyDirectory: agyDirectory)
        return (detected.model, detected.notes, nil)
    case .superEngineering:
        let candidates = [
            normalizePath(worktreePath, resolveSymlinks: false),
            normalizePath(worktreePath, resolveSymlinks: true),
        ]
        do {
            let providers = try querySuperEngineeringProviders(
                databasePath: superDBPath, worktreePaths: candidates)
            guard let latest = providers.first else {
                return (
                    nil, [], "No super.engineering conversation found for worktree \(worktreePath)."
                )
            }
            var notes: [String] = []
            let distinct = Array(Set(providers)).sorted()
            if distinct.count > 1 {
                notes.append(
                    "Multiple super.engineering providers found for \(worktreePath) (\(distinct.joined(separator: ", "))); using most recent: \(latest)."
                )
            }
            guard latest == "codex" else {
                return (
                    nil,
                    notes,
                    "Unsupported super.engineering provider '\(latest)' for worktree \(worktreePath). Only Codex and Antigravity are supported."
                )
            }
            return (.sol, notes, nil)
        } catch {
            return (nil, [], "\(error)")
        }
    case .unknown:
        return (
            nil,
            [],
            "Worktree path \(worktreePath) is outside Codex, Antigravity, and super.engineering roots."
        )
    }
}

/// Discovers the original PR worktree and resolves reviewer and author models.
func discoverLoopContext(
    canonicalRepoPath: String,
    branch: String,
    headSHA: String,
    action: LoopAction,
    reviewerOverride: [AgentModel]? = nil,
    reviewAll: Bool = false,
    authorOverride: AgentModel? = nil,
    targetModel: AgentModel? = nil,
    superDBPath: String,
    agyDirectory: String? = nil,
    homeDirectory: String,
    requireClean: Bool
) -> DiscoveryOutput {
    do {
        let porcelain = try git(canonicalRepoPath, ["worktree", "list", "--porcelain"])
        let entries = parseWorktreeList(porcelain)
        // Resolve symlinks on homeDirectory if it exists so /var vs /private/var never mismatches git.
        let resolvedHome = normalizePath(homeDirectory, resolveSymlinks: true)
        let resolvedAgyDir = agyDirectory ?? "\(resolvedHome)/.gemini/antigravity"
        let normalizedEntries = entries.map {
            WorktreeEntry(
                path: normalizePath($0.path, resolveSymlinks: true),
                head: $0.head,
                branch: $0.branch,
                isDetached: $0.isDetached
            )
        }

        let worktree = try locateWorktree(
            entries: normalizedEntries,
            branch: branch,
            headSHA: headSHA,
            homeDirectory: resolvedHome
        )

        var notes: [String] = []
        var detectedAuthor: AgentModel?
        var detectionFailure: String?

        if let worktree {
            let needsDetection =
                switch action {
                case .ask: targetModel == nil
                case .address: authorOverride == nil
                case .review: authorOverride == nil
                }
            if needsDetection {
                let result = resolveAuthorModel(
                    worktreePath: worktree.path,
                    homeDirectory: resolvedHome,
                    superDBPath: superDBPath,
                    agyDirectory: resolvedAgyDir
                )
                detectedAuthor = result.model
                notes.append(contentsOf: result.notes)
                detectionFailure = result.reason
            }
        } else {
            detectionFailure =
                "No local worktree found for branch '\(branch)' or detached commit \(headSHA)."
        }

        let resolvedAuthor: AgentModel
        let resolvedReviewers: [AgentModel]

        switch action {
        case .ask:
            guard worktree != nil else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: nil,
                    author: targetModel?.profile,
                    reviewers: [],
                    notes: notes,
                    error: detectionFailure
                )
            }
            guard let model = targetModel ?? detectedAuthor else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: worktree?.path,
                    author: nil,
                    reviewers: [],
                    notes: notes,
                    error: detectionFailure ?? "Could not determine model for /ask."
                )
            }
            resolvedAuthor = model
            resolvedReviewers = []

        case .address:
            guard let author = authorOverride ?? detectedAuthor else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: worktree?.path,
                    author: nil,
                    reviewers: [],
                    notes: notes,
                    error: detectionFailure ?? "Could not determine author model."
                )
            }
            resolvedAuthor = author
            resolvedReviewers = []

        case .review:
            if let explicitAuthor = authorOverride ?? detectedAuthor {
                resolvedAuthor = explicitAuthor
            } else if let firstReviewer = reviewerOverride?.first, !reviewAll {
                let fallback = firstReviewer.defaultReviewer
                resolvedAuthor = fallback
                notes.append(
                    "Author model fallback '\(fallback.rawValue)' used from /review \(firstReviewer.rawValue) override."
                )
            } else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: worktree?.path,
                    author: nil,
                    reviewers: (reviewerOverride ?? []).map(\.profile),
                    notes: notes,
                    error: detectionFailure ?? "Could not determine author model."
                )
            }

            if reviewAll {
                resolvedReviewers = resolvedAuthor.allReviewers
            } else if let reviewerOverride, !reviewerOverride.isEmpty {
                resolvedReviewers = reviewerOverride
            } else {
                resolvedReviewers = [resolvedAuthor.defaultReviewer]
            }
        }

        if requireClean {
            guard let worktree else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: nil,
                    author: resolvedAuthor.profile,
                    reviewers: resolvedReviewers.map(\.profile),
                    notes: notes,
                    error:
                        "No local worktree found for branch '\(branch)' or detached commit \(headSHA)."
                )
            }
            guard FileManager.default.fileExists(atPath: worktree.path) else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: worktree.path,
                    author: resolvedAuthor.profile,
                    reviewers: resolvedReviewers.map(\.profile),
                    notes: notes,
                    error: "Worktree directory does not exist: \(worktree.path)."
                )
            }
            guard worktree.head == headSHA else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: worktree.path,
                    author: resolvedAuthor.profile,
                    reviewers: resolvedReviewers.map(\.profile),
                    notes: notes,
                    error:
                        "Worktree \(worktree.path) HEAD (\(worktree.head)) does not match PR head (\(headSHA))."
                )
            }
            let statusOutput = try git(worktree.path, ["status", "--porcelain"])
            if !statusOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: worktree.path,
                    author: resolvedAuthor.profile,
                    reviewers: resolvedReviewers.map(\.profile),
                    notes: notes,
                    error: "Worktree \(worktree.path) has uncommitted changes."
                )
            }
        }

        return DiscoveryOutput(
            status: "ok",
            worktreePath: worktree?.path,
            author: resolvedAuthor.profile,
            reviewers: resolvedReviewers.map(\.profile),
            notes: notes,
            error: nil
        )
    } catch {
        return DiscoveryOutput(
            status: "error",
            worktreePath: nil,
            author: nil,
            reviewers: [],
            notes: [],
            error: "\(error)"
        )
    }
}

/// Builds the Codex `-c skills.config=...` TOML array disabling all non-allowlisted skills.
func buildCodexSkillsConfig(
    repoPath: String,
    homeDirectory: String,
    allowedNames: Set<String>
) -> String {
    let fm = FileManager.default
    let roots = [
        normalizePath(repoPath, resolveSymlinks: true) + "/.codex/skills",
        normalizePath(repoPath, resolveSymlinks: true) + "/.agents/skills",
        normalizePath(homeDirectory, resolveSymlinks: true) + "/.codex/skills",
        normalizePath(homeDirectory, resolveSymlinks: true) + "/.codex/skills/.system",
        normalizePath(homeDirectory, resolveSymlinks: true) + "/.agents/skills",
    ]

    var seenPaths = Set<String>()
    var disabledPaths: [String] = []

    for root in roots {
        guard let children = try? fm.contentsOfDirectory(atPath: root) else { continue }
        for child in children.sorted() {
            if child.hasPrefix(".") { continue }
            let skillFile = normalizePath("\(root)/\(child)/SKILL.md", resolveSymlinks: true)
            guard fm.fileExists(atPath: skillFile) else { continue }
            guard !allowedNames.contains(child) else { continue }
            if seenPaths.insert(skillFile).inserted {
                disabledPaths.append(skillFile)
            }
        }
    }

    let entries = disabledPaths.sorted().map { path -> String in
        let escaped =
            path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "{path=\"\(escaped)\",enabled=false}"
    }
    return "[\(entries.joined(separator: ","))]"
}

enum CheckRunStatus: String, Codable, Equatable {
    case queued
    case inProgress = "in_progress"
    case completed
}

struct CheckRunOutput: Codable, Equatable {
    let title: String
    let summary: String
}

struct CheckRunPayload: Codable, Equatable {
    let name: String?
    let headSHA: String?
    let detailsURL: String?
    let externalID: String?
    let status: CheckRunStatus
    let startedAt: String?
    let completedAt: String?
    let conclusion: String?
    let output: CheckRunOutput?

    enum CodingKeys: String, CodingKey {
        case name
        case headSHA = "head_sha"
        case detailsURL = "details_url"
        case externalID = "external_id"
        case status
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case conclusion
        case output
    }
}

/// Builds a GitHub Checks API payload for creating or updating a PR check run.
func buildCheckRunPayload(
    name: String? = nil,
    headSHA: String? = nil,
    status: CheckRunStatus,
    conclusion: String? = nil,
    title: String? = nil,
    summary: String? = nil,
    detailsURL: String? = nil,
    externalID: String? = nil,
    timestamp: String = ISO8601DateFormatter().string(from: Date())
) throws -> CheckRunPayload {
    if status == .completed {
        guard let conclusion, !conclusion.isEmpty else {
            throw ReviewLoopError(description: "Missing --conclusion for completed check run.")
        }
    } else if let conclusion, !conclusion.isEmpty {
        throw ReviewLoopError(
            description: "Unexpected --conclusion for \(status.rawValue) check run.")
    }

    let output: CheckRunOutput?
    if let title, !title.isEmpty {
        output = CheckRunOutput(title: title, summary: summary ?? "")
    } else if let summary, !summary.isEmpty {
        output = CheckRunOutput(title: name ?? status.rawValue, summary: summary)
    } else {
        output = nil
    }

    return CheckRunPayload(
        name: name?.isEmpty == true ? nil : name,
        headSHA: headSHA?.isEmpty == true ? nil : headSHA,
        detailsURL: detailsURL?.isEmpty == true ? nil : detailsURL,
        externalID: externalID?.isEmpty == true ? nil : externalID,
        status: status,
        startedAt: status == .inProgress ? timestamp : nil,
        completedAt: status == .completed ? timestamp : nil,
        conclusion: status == .completed ? conclusion : nil,
        output: output
    )
}

enum CheckRunRequestMode: Equatable {
    case create
    case update(String)
}

/// Chooses create or update mode so completed check runs are recreated on retry instead of patched.
func resolveCheckRunMode(
    checkRunID: String?,
    status: CheckRunStatus,
    recreateIfCompleted: Bool,
    existingStatus: () throws -> CheckRunStatus?
) throws -> CheckRunRequestMode {
    guard let checkRunID, !checkRunID.isEmpty else {
        return .create
    }
    if recreateIfCompleted && status != .completed {
        if try existingStatus() == .completed {
            return .create
        }
    }
    return .update(checkRunID)
}

private func fetchCheckRunStatus(repo: String, checkRunID: String) throws -> CheckRunStatus? {
    let result = try runProcess(
        arguments: [
            "gh", "api",
            "-H", "Accept: application/vnd.github+json",
            "repos/\(repo)/check-runs/\(checkRunID)",
            "--jq", ".status",
        ]
    )
    guard result.exitCode == 0 else {
        let details = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        throw ReviewLoopError(
            description: "gh api GET repos/\(repo)/check-runs/\(checkRunID) failed: \(details)")
    }
    let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return CheckRunStatus(rawValue: raw)
}

private func submitCheckRun(
    repo: String,
    checkRunID: String?,
    name: String?,
    headSHA: String?,
    status: CheckRunStatus,
    conclusion: String?,
    title: String?,
    summary: String?,
    detailsURL: String?,
    externalID: String?,
    recreateIfCompleted: Bool
) throws -> String {
    if recreateIfCompleted && status != .completed {
        guard let name, !name.isEmpty, let headSHA, !headSHA.isEmpty else {
            throw ReviewLoopError(
                description: "--recreate-if-completed requires --name and --head-sha.")
        }
    }

    let mode = try resolveCheckRunMode(
        checkRunID: checkRunID,
        status: status,
        recreateIfCompleted: recreateIfCompleted,
        existingStatus: {
            try fetchCheckRunStatus(repo: repo, checkRunID: checkRunID!)
        }
    )

    let isUpdate: Bool
    let targetID: String?
    switch mode {
    case .create:
        guard let name, !name.isEmpty, let headSHA, !headSHA.isEmpty else {
            throw ReviewLoopError(
                description: "Creating a check run requires --name and --head-sha.")
        }
        isUpdate = false
        targetID = nil
    case .update(let existingID):
        isUpdate = true
        targetID = existingID
    }

    let payload = try buildCheckRunPayload(
        name: name,
        headSHA: isUpdate ? nil : headSHA,
        status: status,
        conclusion: conclusion,
        title: title,
        summary: summary,
        detailsURL: detailsURL,
        externalID: externalID
    )
    let jsonData = try JSONEncoder().encode(payload)

    let method = isUpdate ? "PATCH" : "POST"
    let endpoint =
        isUpdate
        ? "repos/\(repo)/check-runs/\(targetID!)"
        : "repos/\(repo)/check-runs"
    let result = try runProcess(
        arguments: [
            "gh", "api",
            "--method", method,
            "-H", "Accept: application/vnd.github+json",
            endpoint,
            "--input", "-",
            "--jq", ".id",
        ],
        stdinData: jsonData
    )
    guard result.exitCode == 0 else {
        let details = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        throw ReviewLoopError(description: "gh api \(method) \(endpoint) failed: \(details)")
    }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
}

private let supportedReactions: Set<String> = [
    "+1", "-1", "laugh", "confused", "heart", "hooray", "rocket", "eyes",
]

/// Returns the GitHub reactions API endpoint for comment events, or nil when reactions do not apply.
func commentReactionEndpoint(repo: String, eventName: String, commentID: String?) -> String? {
    guard let commentID = commentID?.trimmingCharacters(in: .whitespacesAndNewlines),
        !commentID.isEmpty
    else {
        return nil
    }
    switch eventName {
    case "issue_comment":
        return "repos/\(repo)/issues/comments/\(commentID)/reactions"
    case "pull_request_review_comment":
        return "repos/\(repo)/pulls/comments/\(commentID)/reactions"
    default:
        return nil
    }
}

private func addCommentReaction(
    repo: String,
    eventName: String,
    commentID: String?,
    content: String
) throws {
    guard supportedReactions.contains(content) else {
        throw ReviewLoopError(description: "Unsupported reaction content: \(content)")
    }
    guard let endpoint = commentReactionEndpoint(repo: repo, eventName: eventName, commentID: commentID)
    else {
        return
    }
    let result = try runProcess(
        arguments: [
            "gh", "api",
            "--method", "POST",
            "-H", "Accept: application/vnd.github+json",
            endpoint,
            "-f", "content=\(content)",
        ]
    )
    guard result.exitCode == 0 else {
        let details = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        throw ReviewLoopError(description: "gh api POST \(endpoint) failed: \(details)")
    }
}

/// Validates monitor phase identifiers (`review-<model>`, `address`, or `ask`).
func isValidMonitorPhase(_ raw: String) -> Bool {
    if raw == "address" || raw == "ask" {
        return true
    }
    if raw.hasPrefix("review-") {
        let modelName = String(raw.dropFirst("review-".count))
        return AgentModel(rawValue: modelName) != nil
    }
    return false
}

enum MonitorPhaseStatus: String, Codable, Equatable {
    case queued
    case running
    case completed
}

struct MonitorRunRecord: Codable, Equatable {
    let runID: String
    let kind: String?
    let prNumber: Int?
    let prBranch: String?
    let prHeadSHA: String?
    let repository: String?
    let runURL: String?
    let createdAt: String
    let updatedAt: String
}

struct MonitorPhaseRecord: Codable, Equatable {
    let phase: String
    let harness: Harness?
    let botLogin: String?
    let model: String?
    let effort: String?
    let worktreePath: String?
    let prompt: String?
    let streamFile: String?
    let status: MonitorPhaseStatus
    let conclusion: String?
    let startedAt: String?
    let completedAt: String?
    let updatedAt: String
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
}

private func writeJSONAtomically<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    let tmpURL = url.deletingLastPathComponent()
        .appending(path: ".\(url.lastPathComponent).tmp.\(UUID().uuidString)")
    try data.write(to: tmpURL, options: .atomic)
    if FileManager.default.fileExists(atPath: url.path) {
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
    } else {
        try FileManager.default.moveItem(at: tmpURL, to: url)
    }
}

/// Writes or updates run and phase metadata for the local agent monitor UI.
func recordMonitorState(
    monitorDirectory: String,
    runID: String,
    kind: String? = nil,
    phase: String? = nil,
    prNumber: Int? = nil,
    prBranch: String? = nil,
    prHeadSHA: String? = nil,
    repository: String? = nil,
    runURL: String? = nil,
    harness: Harness? = nil,
    botLogin: String? = nil,
    model: String? = nil,
    effort: String? = nil,
    worktreePath: String? = nil,
    prompt: String? = nil,
    streamFile: String? = nil,
    status: MonitorPhaseStatus? = nil,
    conclusion: String? = nil,
    timestamp: String = ISO8601DateFormatter().string(from: Date())
) throws {
    guard !runID.isEmpty, !runID.contains("/"), runID != ".", runID != ".." else {
        throw ReviewLoopError(description: "Invalid --run-id: \(runID)")
    }

    let runDir = URL(fileURLWithPath: monitorDirectory)
        .appending(path: "runs", directoryHint: .isDirectory)
        .appending(path: runID, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

    let runURLFile = runDir.appending(path: "run.json")
    let existingRun: MonitorRunRecord?
    if let data = try? Data(contentsOf: runURLFile) {
        existingRun = try? JSONDecoder().decode(MonitorRunRecord.self, from: data)
    } else {
        existingRun = nil
    }

    let mergedRun = MonitorRunRecord(
        runID: runID,
        kind: nonEmpty(kind) ?? existingRun?.kind,
        prNumber: prNumber ?? existingRun?.prNumber,
        prBranch: nonEmpty(prBranch) ?? existingRun?.prBranch,
        prHeadSHA: nonEmpty(prHeadSHA) ?? existingRun?.prHeadSHA,
        repository: nonEmpty(repository) ?? existingRun?.repository,
        runURL: nonEmpty(runURL) ?? existingRun?.runURL,
        createdAt: existingRun?.createdAt ?? timestamp,
        updatedAt: timestamp
    )
    try writeJSONAtomically(mergedRun, to: runURLFile)

    guard let phase else { return }
    guard isValidMonitorPhase(phase) else {
        throw ReviewLoopError(description: "Invalid --phase value: \(phase)")
    }
    let phaseURLFile = runDir.appending(path: "\(phase).json")
    let existingPhase: MonitorPhaseRecord?
    if let data = try? Data(contentsOf: phaseURLFile) {
        existingPhase = try? JSONDecoder().decode(MonitorPhaseRecord.self, from: data)
    } else {
        existingPhase = nil
    }

    let resolvedStatus = status ?? existingPhase?.status ?? .queued
    let resolvedStartedAt: String? =
        if resolvedStatus == .running {
            existingPhase?.startedAt ?? timestamp
        } else {
            existingPhase?.startedAt
        }
    let resolvedCompletedAt: String? =
        if resolvedStatus == .completed {
            existingPhase?.completedAt ?? timestamp
        } else {
            nil
        }
    let resolvedConclusion: String? =
        if resolvedStatus == .completed {
            nonEmpty(conclusion) ?? existingPhase?.conclusion
        } else {
            nil
        }

    let mergedPhase = MonitorPhaseRecord(
        phase: phase,
        harness: harness ?? existingPhase?.harness,
        botLogin: nonEmpty(botLogin) ?? existingPhase?.botLogin,
        model: nonEmpty(model) ?? existingPhase?.model,
        effort: nonEmpty(effort) ?? existingPhase?.effort,
        worktreePath: nonEmpty(worktreePath) ?? existingPhase?.worktreePath,
        prompt: nonEmpty(prompt) ?? existingPhase?.prompt,
        streamFile: nonEmpty(streamFile) ?? existingPhase?.streamFile,
        status: resolvedStatus,
        conclusion: resolvedConclusion,
        startedAt: resolvedStartedAt,
        completedAt: resolvedCompletedAt,
        updatedAt: timestamp
    )
    try writeJSONAtomically(mergedPhase, to: phaseURLFile)
}

private func parseOptions(_ arguments: [String]) throws -> (
    flags: Set<String>, values: [String: String]
) {
    var flags = Set<String>()
    var values: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let arg = arguments[index]
        guard arg.hasPrefix("--") else {
            throw ReviewLoopError(description: "Unexpected argument: \(arg)")
        }
        let key = String(arg.dropFirst(2))
        if key == "require-clean" || key == "recreate-if-completed" || key == "review-all" {
            flags.insert(key)
            index += 1
        } else {
            guard index + 1 < arguments.count else {
                throw ReviewLoopError(description: "Missing value for --\(key)")
            }
            values[key] = arguments[index + 1]
            index += 2
        }
    }
    return (flags, values)
}

private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}

private func parseOptionalHarness(_ values: [String: String], flag: String) throws -> Harness? {
    guard let raw = values[flag], !raw.isEmpty else { return nil }
    guard let harness = Harness(rawValue: raw) else {
        throw ReviewLoopError(description: "Invalid --\(flag) value: \(raw)")
    }
    return harness
}

private func parseOptionalModel(_ values: [String: String], flag: String) throws -> AgentModel? {
    guard let raw = values[flag], !raw.isEmpty else { return nil }
    guard let model = AgentModel(rawValue: raw.lowercased()) else {
        throw ReviewLoopError(description: "Invalid --\(flag) value: \(raw)")
    }
    return model
}

private func parseOptionalModelList(_ values: [String: String], flag: String) throws -> [AgentModel]?
{
    guard let raw = values[flag], !raw.isEmpty else { return nil }
    let tokens =
        raw
        .split(whereSeparator: { $0 == "," || $0.isWhitespace })
        .map { String($0).lowercased() }
        .filter { !$0.isEmpty }
    guard !tokens.isEmpty else { return nil }
    var seen = Set<AgentModel>()
    var result: [AgentModel] = []
    for token in tokens {
        guard let model = AgentModel(rawValue: token) else {
            throw ReviewLoopError(description: "Invalid --\(flag) value: \(token)")
        }
        if seen.insert(model).inserted {
            result.append(model)
        }
    }
    return result
}

private func runCLI() -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let subcommand = args.first else {
        FileHandle.standardError.write(
            Data(
                "Usage: agent_review_loop.swift <parse-trigger|parse-ask|discover|codex-skills-config|check-run|react|monitor-record> [options]\n"
                    .utf8))
        return 2
    }

    do {
        let parsed = try parseOptions(Array(args.dropFirst()))
        let home = parsed.values["home"] ?? FileManager.default.homeDirectoryForCurrentUser.path

        switch subcommand {
        case "parse-trigger":
            guard let event = parsed.values["event"] else {
                throw ReviewLoopError(description: "Missing --event")
            }
            let plan = try parseTrigger(
                eventName: event,
                commentBody: parsed.values["body"],
                dispatchAction: parsed.values["action"],
                dispatchReviewer: parsed.values["reviewer"],
                dispatchAuthor: parsed.values["author"],
                dispatchPRNumber: parsed.values["pr-number"],
                dispatchDryRun: parsed.values["dry-run"]
            )
            print(try encodeJSON(plan))
            return 0

        case "parse-ask":
            guard let event = parsed.values["event"] else {
                throw ReviewLoopError(description: "Missing --event")
            }
            let plan = try parseAsk(
                eventName: event,
                commentBody: parsed.values["body"],
                dispatchModel: parsed.values["model"],
                dispatchInstructions: parsed.values["instructions"],
                dispatchPRNumber: parsed.values["pr-number"],
                dispatchDryRun: parsed.values["dry-run"]
            )
            print(try encodeJSON(plan))
            return 0

        case "discover":
            guard let repo = parsed.values["repo"],
                let branch = parsed.values["branch"],
                let headSHA = parsed.values["head-sha"],
                let actionText = parsed.values["action"],
                let action = LoopAction(rawValue: actionText)
            else {
                throw ReviewLoopError(
                    description: "Missing required flags: --repo, --branch, --head-sha, --action"
                )
            }
            let reviewerOverride = try parseOptionalModelList(parsed.values, flag: "reviewers")
            let authorOverride = try parseOptionalModel(parsed.values, flag: "author")
            let targetModel = try parseOptionalModel(parsed.values, flag: "model")
            let superDB =
                parsed.values["super-db"]
                ?? "\(home)/.super.engineering/db/super.engineering.db"
            let agyDir = parsed.values["agy-dir"] ?? "\(home)/.gemini/antigravity"
            let result = discoverLoopContext(
                canonicalRepoPath: repo,
                branch: branch,
                headSHA: headSHA,
                action: action,
                reviewerOverride: reviewerOverride,
                reviewAll: parsed.flags.contains("review-all"),
                authorOverride: authorOverride,
                targetModel: targetModel,
                superDBPath: superDB,
                agyDirectory: agyDir,
                homeDirectory: home,
                requireClean: parsed.flags.contains("require-clean")
            )
            print(try encodeJSON(result))
            return result.status == "ok" ? 0 : 1

        case "codex-skills-config":
            guard let repo = parsed.values["repo"] else {
                throw ReviewLoopError(description: "Missing --repo")
            }
            let allowList = (parsed.values["allow"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            print(
                buildCodexSkillsConfig(
                    repoPath: repo, homeDirectory: home, allowedNames: Set(allowList)))
            return 0

        case "check-run":
            guard let repo = parsed.values["repo"],
                let statusText = parsed.values["status"],
                let status = CheckRunStatus(rawValue: statusText)
            else {
                throw ReviewLoopError(
                    description:
                        "Missing or invalid flags: --repo, --status (queued|in_progress|completed)"
                )
            }
            let checkRunID = try submitCheckRun(
                repo: repo,
                checkRunID: parsed.values["check-run-id"],
                name: parsed.values["name"],
                headSHA: parsed.values["head-sha"],
                status: status,
                conclusion: parsed.values["conclusion"],
                title: parsed.values["title"],
                summary: parsed.values["summary"],
                detailsURL: parsed.values["details-url"],
                externalID: parsed.values["external-id"],
                recreateIfCompleted: parsed.flags.contains("recreate-if-completed")
            )
            print(checkRunID)
            return 0

        case "react":
            guard let repo = parsed.values["repo"], !repo.isEmpty,
                let event = parsed.values["event"], !event.isEmpty
            else {
                throw ReviewLoopError(description: "Missing required flags: --repo, --event")
            }
            let content = parsed.values["content"] ?? "eyes"
            try addCommentReaction(
                repo: repo,
                eventName: event,
                commentID: parsed.values["comment-id"],
                content: content
            )
            return 0

        case "monitor-record":
            guard let runID = parsed.values["run-id"], !runID.isEmpty else {
                throw ReviewLoopError(description: "Missing --run-id")
            }
            let monitorDirectory =
                parsed.values["monitor-dir"]
                ?? ProcessInfo.processInfo.environment["AGENT_MONITOR_DIR"]
                ?? "\(home)/.clinical-agent-monitor"
            let phase: String?
            if let raw = parsed.values["phase"], !raw.isEmpty {
                guard isValidMonitorPhase(raw) else {
                    throw ReviewLoopError(description: "Invalid --phase value: \(raw)")
                }
                phase = raw
            } else {
                phase = nil
            }
            let status: MonitorPhaseStatus?
            if let raw = parsed.values["status"], !raw.isEmpty {
                guard let parsedStatus = MonitorPhaseStatus(rawValue: raw) else {
                    throw ReviewLoopError(description: "Invalid --status value: \(raw)")
                }
                status = parsedStatus
            } else {
                status = nil
            }
            let prNumber: Int?
            if let raw = parsed.values["pr-number"], !raw.isEmpty {
                prNumber = Int(raw)
            } else {
                prNumber = nil
            }
            let harness = try parseOptionalHarness(parsed.values, flag: "harness")
            try recordMonitorState(
                monitorDirectory: monitorDirectory,
                runID: runID,
                kind: parsed.values["kind"],
                phase: phase,
                prNumber: prNumber,
                prBranch: parsed.values["pr-branch"],
                prHeadSHA: parsed.values["head-sha"],
                repository: parsed.values["repo"],
                runURL: parsed.values["run-url"],
                harness: harness,
                botLogin: parsed.values["bot-login"],
                model: parsed.values["model"],
                effort: parsed.values["effort"],
                worktreePath: parsed.values["worktree"],
                prompt: parsed.values["prompt"],
                streamFile: parsed.values["stream-file"],
                status: status,
                conclusion: parsed.values["conclusion"]
            )
            return 0

        default:
            throw ReviewLoopError(description: "Unknown subcommand: \(subcommand)")
        }
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        return 1
    }
}

#if !AGENT_REVIEW_LOOP_TESTS
    exit(runCLI())
#endif
