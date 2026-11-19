import Foundation
import SQLite3

struct ReviewLoopError: Error, CustomStringConvertible {
    let description: String
}

enum Harness: String, Codable, Equatable {
    case codex
    case antigravity

    var other: Harness {
        switch self {
        case .codex: .antigravity
        case .antigravity: .codex
        }
    }

    var botLogin: String {
        switch self {
        case .codex: "clinical-codex[bot]"
        case .antigravity: "clinical-antigravity[bot]"
        }
    }
}

enum LoopAction: String, Codable, Equatable {
    case review
    case address
    case mention
}

struct TriggerPlan: Codable, Equatable {
    let action: LoopAction
    let prNumber: Int?
    let reviewerOverride: Harness?
    let dryRun: Bool
}

struct MentionPlan: Codable, Equatable {
    let matched: Bool
    let harness: Harness?
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
    let authorHarness: Harness?
    let reviewerHarness: Harness?
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

/// Parses `/review [codex|antigravity]` or `/address` PR comments and workflow_dispatch inputs.
func parseTrigger(
    eventName: String,
    commentBody: String? = nil,
    dispatchAction: String? = nil,
    dispatchReviewer: String? = nil,
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
            if tokens.count == 1 {
                return TriggerPlan(
                    action: .review, prNumber: nil, reviewerOverride: nil, dryRun: false)
            }
            guard tokens.count == 2, let harness = Harness(rawValue: tokens[1]) else {
                throw ReviewLoopError(
                    description:
                        "Invalid /review command. Use `/review`, `/review codex`, or `/review antigravity`."
                )
            }
            return TriggerPlan(
                action: .review, prNumber: nil, reviewerOverride: harness, dryRun: false)
        case "/address":
            guard tokens.count == 1 else {
                throw ReviewLoopError(
                    description: "Invalid /address command. Use `/address` with no arguments.")
            }
            return TriggerPlan(
                action: .address, prNumber: nil, reviewerOverride: nil, dryRun: false)
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
            let action = LoopAction(rawValue: actionText)
        else {
            throw ReviewLoopError(
                description: "Invalid workflow_dispatch action. Use `review` or `address`.")
        }
        let reviewerText = (dispatchReviewer ?? "auto").trimmingCharacters(
            in: .whitespacesAndNewlines)
        let reviewerOverride: Harness?
        if reviewerText.isEmpty || reviewerText == "auto" {
            reviewerOverride = nil
        } else if let parsed = Harness(rawValue: reviewerText), action == .review {
            reviewerOverride = parsed
        } else {
            throw ReviewLoopError(
                description:
                    "Invalid reviewer option '\(reviewerText)' for action '\(action.rawValue)'.")
        }
        let dryRun =
            (dispatchDryRun ?? "false").trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        return TriggerPlan(
            action: action,
            prNumber: prNumber,
            reviewerOverride: reviewerOverride,
            dryRun: dryRun
        )

    default:
        throw ReviewLoopError(description: "Unsupported event: \(eventName)")
    }
}

private func isASCIIAlnum(_ ch: Character) -> Bool {
    guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return false }
    return (scalar.value >= 48 && scalar.value <= 57)
        || (scalar.value >= 65 && scalar.value <= 90)
        || (scalar.value >= 97 && scalar.value <= 122)
}

private func isMentionPrefixInvalid(_ ch: Character?) -> Bool {
    guard let ch else { return false }
    return isASCIIAlnum(ch) || ch == "." || ch == "_" || ch == "-" || ch == "+"
}

private func isMentionSuffixInvalid(_ ch: Character?) -> Bool {
    guard let ch else { return false }
    return isASCIIAlnum(ch) || ch == "_" || ch == "-" || ch == "["
}

private func scanBotMentions(in text: String) -> [(harness: Harness, range: Range<String.Index>)] {
    let targets: [(handle: String, harness: Harness)] = [
        ("@clinical-codex", .codex),
        ("@clinical-antigravity", .antigravity),
    ]
    var matches: [(harness: Harness, range: Range<String.Index>)] = []
    var index = text.startIndex

    while index < text.endIndex {
        if text[index] == "@" {
            let beforeChar = index > text.startIndex ? text[text.index(before: index)] : nil
            if !isMentionPrefixInvalid(beforeChar) {
                var matched = false
                for target in targets {
                    guard
                        let handleEnd = text.index(
                            index, offsetBy: target.handle.count, limitedBy: text.endIndex)
                    else { continue }
                    if text[index..<handleEnd].lowercased() == target.handle {
                        var tokenEnd = handleEnd
                        if let botEnd = text.index(
                            handleEnd, offsetBy: 5, limitedBy: text.endIndex),
                            text[handleEnd..<botEnd].lowercased() == "[bot]"
                        {
                            tokenEnd = botEnd
                        }
                        let afterChar = tokenEnd < text.endIndex ? text[tokenEnd] : nil
                        if !isMentionSuffixInvalid(afterChar) {
                            matches.append((target.harness, index..<tokenEnd))
                            index = tokenEnd
                            matched = true
                            break
                        }
                    }
                }
                if matched { continue }
            }
        }
        index = text.index(after: index)
    }
    return matches
}

private func stripBlockquoteLines(from text: String) -> String {
    text
        .components(separatedBy: "\n")
        .filter { line in
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            return !trimmed.hasPrefix(">")
        }
        .joined(separator: "\n")
}

private func fencePrefix(in line: String) -> (char: Character, length: Int)? {
    var spaces = 0
    var idx = line.startIndex
    while idx < line.endIndex && line[idx] == " " && spaces < 3 {
        spaces += 1
        idx = line.index(after: idx)
    }
    guard idx < line.endIndex else { return nil }
    let ch = line[idx]
    guard ch == "`" || ch == "~" else { return nil }
    var length = 0
    while idx < line.endIndex && line[idx] == ch {
        length += 1
        idx = line.index(after: idx)
    }
    guard length >= 3 else { return nil }
    if ch == "`" && line[idx...].contains("`") {
        return nil
    }
    return (ch, length)
}

private func isClosingFence(_ line: String, char: Character, minLength: Int) -> Bool {
    var spaces = 0
    var idx = line.startIndex
    while idx < line.endIndex && line[idx] == " " && spaces < 3 {
        spaces += 1
        idx = line.index(after: idx)
    }
    var length = 0
    while idx < line.endIndex && line[idx] == char {
        length += 1
        idx = line.index(after: idx)
    }
    guard length >= minLength else { return false }
    return line[idx...].allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" }
}

private func stripInlineCodeSpans(from line: String) -> String {
    var result = ""
    var index = line.startIndex
    while index < line.endIndex {
        if line[index] == "`" {
            var tickEnd = index
            while tickEnd < line.endIndex && line[tickEnd] == "`" {
                tickEnd = line.index(after: tickEnd)
            }
            let tickCount = line.distance(from: index, to: tickEnd)
            var search = tickEnd
            var foundCloseEnd: String.Index?
            while search < line.endIndex {
                if line[search] == "`" {
                    var closeEnd = search
                    while closeEnd < line.endIndex && line[closeEnd] == "`" {
                        closeEnd = line.index(after: closeEnd)
                    }
                    if line.distance(from: search, to: closeEnd) == tickCount {
                        foundCloseEnd = closeEnd
                        break
                    }
                    search = closeEnd
                } else {
                    search = line.index(after: search)
                }
            }
            if let closeEnd = foundCloseEnd {
                index = closeEnd
                continue
            }
            result.append(contentsOf: line[index..<tickEnd])
            index = tickEnd
            continue
        }
        result.append(line[index])
        index = line.index(after: index)
    }
    return result
}

private func stripCodeAndQuotes(from text: String) -> String {
    let lines = stripBlockquoteLines(from: text).components(separatedBy: "\n")
    var output: [String] = []
    var lineIndex = 0
    while lineIndex < lines.count {
        let line = lines[lineIndex]
        if let fence = fencePrefix(in: line) {
            var closeIndex = lineIndex + 1
            var foundClose = false
            while closeIndex < lines.count {
                if isClosingFence(lines[closeIndex], char: fence.char, minLength: fence.length) {
                    foundClose = true
                    break
                }
                closeIndex += 1
            }
            if foundClose {
                lineIndex = closeIndex + 1
                continue
            }
        }
        output.append(stripInlineCodeSpans(from: line))
        lineIndex += 1
    }
    return output.joined(separator: "\n")
}

private func removeRanges(_ ranges: [Range<String.Index>], from text: String) -> String {
    var result = text
    for range in ranges.reversed() {
        result.removeSubrange(range)
    }
    return result
}

/// Parses `@clinical-codex` or `@clinical-antigravity` PR comment mentions and workflow_dispatch inputs.
func parseMention(
    eventName: String,
    commentBody: String? = nil,
    dispatchBot: String? = nil,
    dispatchInstructions: String? = nil,
    dispatchPRNumber: String? = nil,
    dispatchDryRun: String? = nil
) throws -> MentionPlan {
    switch eventName {
    case "issue_comment", "pull_request_review_comment", "pull_request_review":
        let raw = (commentBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return MentionPlan(
                matched: false, harness: nil, prNumber: nil, instructions: nil, dryRun: false)
        }

        let scanText = stripCodeAndQuotes(from: raw)
        let matches = scanBotMentions(in: scanText)
        let distinctHarnesses = Set(matches.map(\.harness))

        guard !distinctHarnesses.isEmpty else {
            return MentionPlan(
                matched: false, harness: nil, prNumber: nil, instructions: nil, dryRun: false)
        }
        guard distinctHarnesses.count == 1, let harness = distinctHarnesses.first else {
            throw ReviewLoopError(
                description:
                    "Both @clinical-codex and @clinical-antigravity were tagged in the same comment. Tag only one bot per comment."
            )
        }

        let unquoted = stripBlockquoteLines(from: raw)
        let unquotedMatches = scanBotMentions(in: unquoted)
        let remaining = removeRanges(unquotedMatches.map(\.range), from: unquoted)
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,")))
        guard !remaining.isEmpty else {
            let tag = harness == .codex ? "@clinical-codex" : "@clinical-antigravity"
            throw ReviewLoopError(description: "Please include instructions when tagging \(tag).")
        }

        return MentionPlan(
            matched: true, harness: harness, prNumber: nil, instructions: raw, dryRun: false)

    case "workflow_dispatch":
        guard let prText = dispatchPRNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
            let prNumber = Int(prText), prNumber > 0
        else {
            throw ReviewLoopError(description: "Invalid workflow_dispatch pr_number.")
        }
        guard let botText = dispatchBot?.trimmingCharacters(in: .whitespacesAndNewlines),
            let harness = Harness(rawValue: botText)
        else {
            throw ReviewLoopError(
                description: "Invalid workflow_dispatch bot. Use `codex` or `antigravity`.")
        }
        let instructions = (dispatchInstructions ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !instructions.isEmpty else {
            throw ReviewLoopError(
                description: "Invalid workflow_dispatch instructions: cannot be empty.")
        }
        let dryRun =
            (dispatchDryRun ?? "false").trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        return MentionPlan(
            matched: true,
            harness: harness,
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
    // - .super.engineering/worktrees/clinical-swift/<name>
    if components.count == 4 && components[0] == ".codex" && components[1] == "worktrees"
        && components[3] == "clinical-swift"
    {
        return .codex
    }
    if components.count == 5 && components[0] == ".gemini" && components[1] == "antigravity"
        && components[2] == "worktrees" && components[3] == "clinical-swift"
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

private func resolveAuthorHarness(
    worktreePath: String,
    homeDirectory: String,
    superDBPath: String
) -> (harness: Harness?, notes: [String], reason: String?) {
    switch classifyWorktreePath(worktreePath, homeDirectory: homeDirectory) {
    case .codex:
        return (.codex, [], nil)
    case .antigravity:
        return (.antigravity, [], nil)
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
            return (.codex, notes, nil)
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

/// Discovers the original PR worktree and resolves reviewer and author harnesses.
func discoverLoopContext(
    canonicalRepoPath: String,
    branch: String,
    headSHA: String,
    action: LoopAction,
    reviewerOverride: Harness?,
    targetHarness: Harness? = nil,
    superDBPath: String,
    homeDirectory: String,
    requireClean: Bool
) -> DiscoveryOutput {
    do {
        let porcelain = try git(canonicalRepoPath, ["worktree", "list", "--porcelain"])
        let entries = parseWorktreeList(porcelain)
        // Resolve symlinks on homeDirectory if it exists so /var vs /private/var never mismatches git.
        let resolvedHome = normalizePath(homeDirectory, resolveSymlinks: true)
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
        var detectedAuthor: Harness?
        var detectionFailure: String?

        if let worktree {
            if action == .mention {
                detectedAuthor = targetHarness
            } else {
                let result = resolveAuthorHarness(
                    worktreePath: worktree.path,
                    homeDirectory: resolvedHome,
                    superDBPath: superDBPath
                )
                detectedAuthor = result.harness
                notes.append(contentsOf: result.notes)
                detectionFailure = result.reason
            }
        } else {
            detectionFailure =
                "No local worktree found for branch '\(branch)' or detached commit \(headSHA)."
        }

        let reviewerHarness: Harness?
        let authorHarness: Harness?
        if action == .mention {
            guard let targetHarness else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: worktree?.path,
                    authorHarness: nil,
                    reviewerHarness: nil,
                    notes: notes,
                    error: "Missing --harness for mention discovery."
                )
            }
            guard worktree != nil else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: nil,
                    authorHarness: targetHarness,
                    reviewerHarness: nil,
                    notes: notes,
                    error: detectionFailure
                )
            }
            authorHarness = targetHarness
            reviewerHarness = nil
        } else if let reviewerOverride {
            reviewerHarness = (action == .review) ? reviewerOverride : nil
            if let detectedAuthor {
                authorHarness = detectedAuthor
            } else {
                authorHarness = reviewerOverride.other
                notes.append(
                    "Author harness fallback '\(reviewerOverride.other.rawValue)' used from /review \(reviewerOverride.rawValue) override."
                )
            }
        } else {
            guard let detectedAuthor else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: worktree?.path,
                    authorHarness: nil,
                    reviewerHarness: nil,
                    notes: notes,
                    error: detectionFailure ?? "Could not determine author harness."
                )
            }
            authorHarness = detectedAuthor
            reviewerHarness = (action == .review) ? detectedAuthor.other : nil
        }

        if requireClean {
            guard let worktree else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: nil,
                    authorHarness: authorHarness,
                    reviewerHarness: reviewerHarness,
                    notes: notes,
                    error:
                        "No local worktree found for branch '\(branch)' or detached commit \(headSHA)."
                )
            }
            guard FileManager.default.fileExists(atPath: worktree.path) else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: worktree.path,
                    authorHarness: authorHarness,
                    reviewerHarness: reviewerHarness,
                    notes: notes,
                    error: "Worktree directory does not exist: \(worktree.path)."
                )
            }
            guard worktree.head == headSHA else {
                return DiscoveryOutput(
                    status: "error",
                    worktreePath: worktree.path,
                    authorHarness: authorHarness,
                    reviewerHarness: reviewerHarness,
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
                    authorHarness: authorHarness,
                    reviewerHarness: reviewerHarness,
                    notes: notes,
                    error: "Worktree \(worktree.path) has uncommitted changes."
                )
            }
        }

        return DiscoveryOutput(
            status: "ok",
            worktreePath: worktree?.path,
            authorHarness: authorHarness,
            reviewerHarness: reviewerHarness,
            notes: notes,
            error: nil
        )
    } catch {
        return DiscoveryOutput(
            status: "error",
            worktreePath: nil,
            authorHarness: nil,
            reviewerHarness: nil,
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

enum MonitorPhaseKind: String, Codable, Equatable {
    case review
    case address
    case bot
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
    let phase: MonitorPhaseKind
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
    phase: MonitorPhaseKind? = nil,
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
    let phaseURLFile = runDir.appending(path: "\(phase.rawValue).json")
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
        if key == "require-clean" || key == "recreate-if-completed" {
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

private func runCLI() -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let subcommand = args.first else {
        FileHandle.standardError.write(
            Data(
                "Usage: agent_review_loop.swift <parse-trigger|parse-mention|discover|codex-skills-config|check-run|monitor-record> [options]\n"
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
                dispatchPRNumber: parsed.values["pr-number"],
                dispatchDryRun: parsed.values["dry-run"]
            )
            print(try encodeJSON(plan))
            return 0

        case "parse-mention":
            guard let event = parsed.values["event"] else {
                throw ReviewLoopError(description: "Missing --event")
            }
            let plan = try parseMention(
                eventName: event,
                commentBody: parsed.values["body"],
                dispatchBot: parsed.values["bot"],
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
            let reviewerOverride = try parseOptionalHarness(parsed.values, flag: "reviewer")
            let targetHarness = try parseOptionalHarness(parsed.values, flag: "harness")
            let superDB =
                parsed.values["super-db"]
                ?? "\(home)/.super.engineering/db/super.engineering.db"
            let result = discoverLoopContext(
                canonicalRepoPath: repo,
                branch: branch,
                headSHA: headSHA,
                action: action,
                reviewerOverride: reviewerOverride,
                targetHarness: targetHarness,
                superDBPath: superDB,
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

        case "monitor-record":
            guard let runID = parsed.values["run-id"], !runID.isEmpty else {
                throw ReviewLoopError(description: "Missing --run-id")
            }
            let monitorDirectory =
                parsed.values["monitor-dir"]
                ?? ProcessInfo.processInfo.environment["AGENT_MONITOR_DIR"]
                ?? "\(home)/.clinical-agent-monitor"
            let phase: MonitorPhaseKind?
            if let raw = parsed.values["phase"], !raw.isEmpty {
                guard let parsedPhase = MonitorPhaseKind(rawValue: raw) else {
                    throw ReviewLoopError(description: "Invalid --phase value: \(raw)")
                }
                phase = parsedPhase
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
