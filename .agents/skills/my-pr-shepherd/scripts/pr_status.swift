import Foundation

// MARK: - Constants

let trustedAuthorLogins: Set<String> = [
    "vickychijwani",
    "clinical-pr-shepherd",
    "clinical-pr-shepherd[bot]",
    "clinical-antigravity",
    "clinical-antigravity[bot]",
    "clinical-codex",
    "clinical-codex[bot]",
]

let reviewTriggerAuthorLogins: Set<String> = [
    "vickychijwani",
    "clinical-pr-shepherd",
    "clinical-pr-shepherd[bot]",
]

let ownerLogin = "vickychijwani"
let takeoverMarker = "<!-- pr-shepherd -->"
let skipIOSTestsLabel = "skip-ios-tests"

// MARK: - Input Models

struct PRComment: Codable, Equatable {
    let authorLogin: String
    let body: String
    let createdAt: String
}

struct ReviewThreadComment: Codable, Equatable {
    let authorLogin: String
    let body: String
    let url: String
}

struct ReviewThread: Codable, Equatable {
    let isResolved: Bool
    let path: String
    let line: Int?
    let comments: [ReviewThreadComment]
}

struct CheckEntry: Codable, Equatable {
    let name: String
    let workflowName: String
    let status: String
    let conclusion: String
    let title: String
    let detailsUrl: String
    let startedAt: String
    let completedAt: String
}

struct WorkflowRunEntry: Codable, Equatable {
    let databaseId: Int
    let status: String
    let conclusion: String
    let createdAt: String
    let displayTitle: String
    let url: String
}

struct MainCommit: Codable, Equatable {
    let sha: String
    let subject: String
}

struct PRSnapshotInput {
    let number: Int
    let title: String
    let url: String
    let state: String
    let isDraft: Bool
    let mergeable: String
    let mergeStateStatus: String
    let headRefName: String
    let headRefOid: String
    let baseRefName: String
    let labels: [String]
    let comments: [PRComment]
    let reviewThreads: [ReviewThread]
    let checks: [CheckEntry]
    let reviewLoopRuns: [WorkflowRunEntry]
    let worktreePath: String?
    let mainHeadSha: String?
    let newMainCommits: [MainCommit]
    let now: Date
}

// MARK: - Output Models

struct UnresolvedThreadSummary: Codable, Equatable {
    let path: String
    let line: Int?
    let url: String
    let lastAuthor: String
    let mentionsOwner: Bool
    let excerpt: String
}

struct CheckSummary: Codable, Equatable {
    let name: String
    let workflowName: String
    let status: String
    let conclusion: String
    let detailsUrl: String
}

struct PRStatusReport: Codable, Equatable {
    let number: Int
    let title: String
    let url: String
    let state: String
    let isDraft: Bool
    let skipIOSTests: Bool
    let mergeable: String
    let mergeStateStatus: String
    let hasMergeConflict: Bool
    let headRefName: String
    let headRefOid: String
    let baseRefName: String
    let worktreePath: String?
    let takeoverCommentPosted: Bool
    let reviewCommandPosted: Bool
    let reviewLoopStatus: String
    let reviewLoopDetail: String?
    let unresolvedThreads: [UnresolvedThreadSummary]
    let ciStatus: String
    let ciDetail: String?
    let failingChecks: [CheckSummary]
    let pendingChecks: [CheckSummary]
    let mainHeadSha: String?
    let newMainCommits: [MainCommit]
    let readyForFinalCheck: Bool
}

// MARK: - Pure Classification Logic

func isTrustedAuthor(_ login: String) -> Bool {
    trustedAuthorLogins.contains(login.lowercased())
}

func isReviewTriggerAuthor(_ login: String) -> Bool {
    reviewTriggerAuthorLogins.contains(login.lowercased())
}

func firstLineFirstToken(_ text: String) -> String {
    let firstLine = text.split(whereSeparator: \.isNewline).first ?? ""
    return firstLine.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
}

func parseISO8601(_ value: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = withFraction.date(from: value) {
        return parsed
    }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: value)
}

func isReviewCheckName(_ name: String) -> Bool {
    let lower = name.lowercased()
    return lower == "review" || lower.hasPrefix("review (")
}

func isAddressCheckName(_ name: String) -> Bool {
    let lower = name.lowercased()
    return lower == "address" || lower.hasPrefix("address (")
}

func isReviewLoopCheck(_ check: CheckEntry) -> Bool {
    isReviewCheckName(check.name) || isAddressCheckName(check.name)
}

func checkTimestampKey(_ check: CheckEntry) -> String {
    if !check.startedAt.isEmpty {
        return check.startedAt
    }
    return check.completedAt
}

/// Keeps the most recent check run per logical check identity.
/// Review-loop checks created via the Checks API can attach to arbitrary check suites,
/// so deduplicate them by name alone regardless of workflowName.
func deduplicateChecks(_ checks: [CheckEntry]) -> [CheckEntry] {
    var latestByKey: [String: CheckEntry] = [:]
    var order: [String] = []
    for check in checks {
        let key = isReviewLoopCheck(check)
            ? "review-loop::\(check.name.lowercased())"
            : "\(check.workflowName.lowercased())::\(check.name.lowercased())"
        if let existing = latestByKey[key] {
            if checkTimestampKey(check) >= checkTimestampKey(existing) {
                latestByKey[key] = check
            }
        } else {
            latestByKey[key] = check
            order.append(key)
        }
    }
    return order.compactMap { latestByKey[$0] }
}

func parseWorktreePath(porcelain: String, branch: String, headSha: String) -> String? {
    var currentPath: String?
    var currentBranch: String?
    var currentHead: String?
    var branchMatch: String?
    var headMatch: String?

    func flush() {
        guard let path = currentPath else { return }
        if currentBranch == "refs/heads/\(branch)" {
            branchMatch = path
        } else if currentHead == headSha, headMatch == nil {
            headMatch = path
        }
        currentPath = nil
        currentBranch = nil
        currentHead = nil
    }

    for rawLine in porcelain.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        if line.isEmpty {
            flush()
        } else if line.hasPrefix("worktree ") {
            currentPath = String(line.dropFirst("worktree ".count))
        } else if line.hasPrefix("HEAD ") {
            currentHead = String(line.dropFirst("HEAD ".count))
        } else if line.hasPrefix("branch ") {
            currentBranch = String(line.dropFirst("branch ".count))
        }
    }
    flush()
    return branchMatch ?? headMatch
}

func classifyUnresolvedThreads(_ threads: [ReviewThread]) -> [UnresolvedThreadSummary] {
    threads.compactMap { thread -> UnresolvedThreadSummary? in
        guard !thread.isResolved else { return nil }
        let trusted = thread.comments.filter { isTrustedAuthor($0.authorLogin) }
        guard let last = trusted.last else { return nil }
        let mentionsOwner = trusted.contains { $0.body.lowercased().contains("@\(ownerLogin)") }
        let compactBody = last.body
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = compactBody.count > 160
            ? String(compactBody.prefix(157)) + "..."
            : compactBody
        return UnresolvedThreadSummary(
            path: thread.path,
            line: thread.line,
            url: last.url,
            lastAuthor: last.authorLogin,
            mentionsOwner: mentionsOwner,
            excerpt: excerpt
        )
    }
}

func classifyReviewLoop(
    prTitle: String,
    comments: [PRComment],
    checks: [CheckEntry],
    runs: [WorkflowRunEntry],
    unresolvedCount: Int,
    now: Date
) -> (reviewCommandPosted: Bool, status: String, detail: String?) {
    let trustedComments = comments.filter { isTrustedAuthor($0.authorLogin) }
    let reviewCommands = trustedComments.filter {
        isReviewTriggerAuthor($0.authorLogin) && firstLineFirstToken($0.body) == "/review"
    }
    let latestReviewCommand = reviewCommands.max { $0.createdAt < $1.createdAt }
    let reviewCommandPosted = latestReviewCommand != nil

    let reviewChecks = checks.filter { isReviewCheckName($0.name) }
    let addressChecks = checks.filter { isAddressCheckName($0.name) }
    let allLoopChecks = reviewChecks + addressChecks

    // Ignore skipped workflow runs caused by non-command PR comments.
    let relevantRuns = runs.filter { run in
        guard run.displayTitle == prTitle else { return false }
        let conclusionLower = run.conclusion.lowercased()
        if run.status.lowercased() == "completed" && conclusionLower == "skipped" {
            return false
        }
        if let cmdTime = latestReviewCommand.flatMap({ parseISO8601($0.createdAt) }),
           let runTime = parseISO8601(run.createdAt) {
            return runTime >= cmdTime.addingTimeInterval(-15)
        }
        return true
    }

    let activeRun = relevantRuns.first { $0.status.lowercased() != "completed" }
    let activeCheck = allLoopChecks.first { $0.status.uppercased() != "COMPLETED" }
    if let active = activeRun {
        return (reviewCommandPosted, "in_progress", "Workflow run \(active.databaseId) is \(active.status).")
    }
    if let active = activeCheck {
        return (reviewCommandPosted, "in_progress", "Check '\(active.name)' is \(active.status).")
    }

    let latestRun = relevantRuns.max { $0.createdAt < $1.createdAt }

    // Check explicit failures on head check runs or latest workflow run.
    let failedChecks = allLoopChecks.filter { check in
        let conclusion = check.conclusion.uppercased()
        return conclusion == "FAILURE" || conclusion == "CANCELLED" || conclusion == "TIMED_OUT"
    }
    if let failed = failedChecks.first {
        return (reviewCommandPosted, "failed", "Check '\(failed.name)' ended with \(failed.conclusion).")
    }
    if let run = latestRun {
        let conclusion = run.conclusion.lowercased()
        if conclusion == "failure" || conclusion == "cancelled" || conclusion == "timed_out" {
            return (reviewCommandPosted, "failed", "Workflow run \(run.databaseId) ended with \(run.conclusion).")
        }
    }

    // Check for completed review + address on current head commit.
    let reviewSucceeded = !reviewChecks.isEmpty && reviewChecks.allSatisfy {
        let c = $0.conclusion.uppercased()
        return c == "SUCCESS" || c == "NEUTRAL"
    }
    let addressDone = !addressChecks.isEmpty && addressChecks.allSatisfy { check in
        let c = check.conclusion.uppercased()
        if c == "SUCCESS" || c == "NEUTRAL" {
            return true
        }
        // Address skips cleanly when there are zero unresolved review threads.
        if c == "SKIPPED" && unresolvedCount == 0 {
            return !check.title.lowercased().contains("superseded")
        }
        return false
    }

    if reviewSucceeded && addressDone {
        return (reviewCommandPosted, "complete", nil)
    }

    // When address pushes a fix commit, review/address checks live on the prior SHA,
    // so the completed workflow run for this PR confirms completion.
    if let run = latestRun, run.status.lowercased() == "completed", run.conclusion.lowercased() == "success" {
        return (reviewCommandPosted, "complete", nil)
    }

    if let cmd = latestReviewCommand {
        if let cmdDate = parseISO8601(cmd.createdAt), now.timeIntervalSince(cmdDate) < 180 {
            return (true, "pending_start", "Waiting for Agent review loop workflow to start.")
        }
        return (true, "not_started", "/review comment exists but no review loop run was found.")
    }

    return (false, "not_started", nil)
}

/// Evaluates CI checks dynamically without hardcoding job names so workflow renames do not break status checks.
func classifyCI(
    checks: [CheckEntry],
    skipIOSTests: Bool
) -> (status: String, detail: String?, failing: [CheckSummary], pending: [CheckSummary]) {
    let ciChecks = checks.filter { check in
        if isReviewLoopCheck(check) { return false }
        let wf = check.workflowName.lowercased()
        if wf == "agent bot trigger" || wf == "agent review loop" { return false }
        return true
    }

    var failing: [CheckSummary] = []
    var pending: [CheckSummary] = []
    var passingCount = 0
    var iosWorkflowChecks: [CheckEntry] = []

    for check in ciChecks {
        let status = check.status.uppercased()
        let conclusion = check.conclusion.uppercased()
        if check.workflowName.lowercased() == "ios tests" {
            iosWorkflowChecks.append(check)
        }

        let summary = CheckSummary(
            name: check.name,
            workflowName: check.workflowName,
            status: status,
            conclusion: conclusion,
            detailsUrl: check.detailsUrl
        )
        if status != "COMPLETED" {
            pending.append(summary)
        } else if conclusion == "SUCCESS" || conclusion == "NEUTRAL" {
            passingCount += 1
        } else if conclusion == "SKIPPED" {
            continue
        } else {
            failing.append(summary)
        }
    }

    // If iOS tests are not skipped by label, ensure the iOS tests workflow actually executed
    // at least one non-skipped job (draft PRs skip the entire workflow).
    let iosTestsUnrun = !skipIOSTests && !iosWorkflowChecks.contains { check in
        let status = check.status.uppercased()
        let conclusion = check.conclusion.uppercased()
        return status != "COMPLETED" || conclusion != "SKIPPED"
    }

    if !failing.isEmpty {
        return ("failing", nil, failing, pending)
    }
    if !pending.isEmpty {
        return ("pending", nil, failing, pending)
    }
    if passingCount == 0 {
        return ("pending", "No passing CI checks reported yet.", failing, pending)
    }
    if iosTestsUnrun {
        return ("pending", "iOS tests have not run yet (add skip-ios-tests before marking ready if not needed).", failing, pending)
    }
    return ("passing", nil, failing, pending)
}

func buildReport(from input: PRSnapshotInput) -> PRStatusReport {
    let dedupedChecks = deduplicateChecks(input.checks)
    let skipIOSTests = input.labels.contains { $0.lowercased() == skipIOSTestsLabel }
    let takeoverCommentPosted = input.comments.contains {
        isTrustedAuthor($0.authorLogin) && $0.body.contains(takeoverMarker)
    }
    let unresolvedThreads = classifyUnresolvedThreads(input.reviewThreads)
    let reviewLoop = classifyReviewLoop(
        prTitle: input.title,
        comments: input.comments,
        checks: dedupedChecks,
        runs: input.reviewLoopRuns,
        unresolvedCount: unresolvedThreads.count,
        now: input.now
    )
    let ci = classifyCI(checks: dedupedChecks, skipIOSTests: skipIOSTests)
    let hasMergeConflict = input.mergeable.uppercased() == "CONFLICTING"
        || input.mergeStateStatus.uppercased() == "DIRTY"

    let readyForFinalCheck = input.state.uppercased() == "OPEN"
        && !input.isDraft
        && !hasMergeConflict
        && reviewLoop.status == "complete"
        && unresolvedThreads.isEmpty
        && ci.status == "passing"

    return PRStatusReport(
        number: input.number,
        title: input.title,
        url: input.url,
        state: input.state,
        isDraft: input.isDraft,
        skipIOSTests: skipIOSTests,
        mergeable: input.mergeable,
        mergeStateStatus: input.mergeStateStatus,
        hasMergeConflict: hasMergeConflict,
        headRefName: input.headRefName,
        headRefOid: input.headRefOid,
        baseRefName: input.baseRefName,
        worktreePath: input.worktreePath,
        takeoverCommentPosted: takeoverCommentPosted,
        reviewCommandPosted: reviewLoop.reviewCommandPosted,
        reviewLoopStatus: reviewLoop.status,
        reviewLoopDetail: reviewLoop.detail,
        unresolvedThreads: unresolvedThreads,
        ciStatus: ci.status,
        ciDetail: ci.detail,
        failingChecks: ci.failing,
        pendingChecks: ci.pending,
        mainHeadSha: input.mainHeadSha,
        newMainCommits: input.newMainCommits,
        readyForFinalCheck: readyForFinalCheck
    )
}

// MARK: - CLI

#if !PR_STATUS_TESTS

struct CLIError: Error, CustomStringConvertible {
    let description: String
}

func runProcess(_ executable: String, _ arguments: [String], cwd: String? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    if let cwd {
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
    }
    process.standardInput = FileHandle.nullDevice
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let errText = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw CLIError(description: "\(executable) \(arguments.joined(separator: " ")) failed: \(errText)")
    }
    return String(decoding: outData, as: UTF8.self)
}

struct CLIOptions {
    let prNumber: Int
    let sinceMain: String?
    let repo: String?
    let noFetch: Bool
}

func parseArgs(_ args: [String]) throws -> CLIOptions {
    var prNumber: Int?
    var sinceMain: String?
    var repo: String?
    var noFetch = false

    var i = 1
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--since-main":
            i += 1
            guard i < args.count else { throw CLIError(description: "Missing value for --since-main.") }
            sinceMain = args[i]
        case "--repo":
            i += 1
            guard i < args.count else { throw CLIError(description: "Missing value for --repo.") }
            repo = args[i]
        case "--no-fetch":
            noFetch = true
        case "-h", "--help":
            throw CLIError(description: "Usage: swift pr_status.swift <pr-number> [--since-main <sha>] [--repo <owner/name>] [--no-fetch]")
        default:
            if prNumber == nil, let parsed = Int(arg) {
                prNumber = parsed
            } else {
                throw CLIError(description: "Unexpected argument '\(arg)'. Usage: swift pr_status.swift <pr-number> [--since-main <sha>] [--repo <owner/name>] [--no-fetch]")
            }
        }
        i += 1
    }

    guard let prNumber else {
        throw CLIError(description: "Usage: swift pr_status.swift <pr-number> [--since-main <sha>] [--repo <owner/name>] [--no-fetch]")
    }
    return CLIOptions(prNumber: prNumber, sinceMain: sinceMain, repo: repo, noFetch: noFetch)
}

func resolveRepo(_ explicit: String?) throws -> (owner: String, name: String) {
    let raw: String
    if let explicit {
        raw = explicit
    } else {
        raw = try runProcess("gh", ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let parts = raw.split(separator: "/").map(String.init)
    guard parts.count == 2 else {
        throw CLIError(description: "Invalid repository '\(raw)'. Expected owner/name.")
    }
    return (parts[0], parts[1])
}

func fetchPRGraphQL(owner: String, name: String, number: Int) throws -> [String: Any] {
    let query = """
    query($owner:String!,$name:String!,$num:Int!){
      repository(owner:$owner,name:$name){
        pullRequest(number:$num){
          number title url state isDraft mergeable mergeStateStatus
          headRefName headRefOid baseRefName
          labels(first:50){ nodes { name } }
          comments(last:100){ nodes { author { login } body createdAt } }
          reviewThreads(first:100){
            nodes {
              isResolved path line
              comments(first:50){ nodes { author { login } body url } }
            }
          }
          commits(last:1){
            nodes {
              commit {
                statusCheckRollup {
                  contexts(first:100){
                    nodes {
                      __typename
                      ... on CheckRun {
                        name status conclusion title detailsUrl startedAt completedAt
                        checkSuite { workflowRun { workflow { name } } }
                      }
                      ... on StatusContext {
                        context state targetUrl createdAt
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    """
    let output = try runProcess("gh", [
        "api", "graphql",
        "-f", "query=\(query)",
        "-F", "owner=\(owner)",
        "-F", "name=\(name)",
        "-F", "num=\(number)",
    ])
    guard let data = output.data(using: .utf8),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let dataNode = root["data"] as? [String: Any],
          let repoNode = dataNode["repository"] as? [String: Any],
          let prNode = repoNode["pullRequest"] as? [String: Any] else {
        throw CLIError(description: "Failed to parse GraphQL response for PR #\(number).")
    }
    return prNode
}

func fetchReviewLoopRuns(owner: String, name: String) -> [WorkflowRunEntry] {
    guard let output = try? runProcess("gh", [
        "run", "list",
        "--repo", "\(owner)/\(name)",
        "--workflow", "agent-review-loop.yml",
        "--limit", "25",
        "--json", "databaseId,status,conclusion,createdAt,displayTitle,url",
    ]),
          let data = output.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return []
    }
    return array.compactMap { item in
        guard let id = item["databaseId"] as? Int,
              let status = item["status"] as? String,
              let createdAt = item["createdAt"] as? String,
              let displayTitle = item["displayTitle"] as? String,
              let url = item["url"] as? String else {
            return nil
        }
        return WorkflowRunEntry(
            databaseId: id,
            status: status,
            conclusion: item["conclusion"] as? String ?? "",
            createdAt: createdAt,
            displayTitle: displayTitle,
            url: url
        )
    }
}

func parseGraphQLPR(_ pr: [String: Any], runs: [WorkflowRunEntry], options: CLIOptions) throws -> PRSnapshotInput {
    let number = pr["number"] as? Int ?? options.prNumber
    let title = pr["title"] as? String ?? ""
    let url = pr["url"] as? String ?? ""
    let state = pr["state"] as? String ?? "UNKNOWN"
    let isDraft = pr["isDraft"] as? Bool ?? false
    let mergeable = pr["mergeable"] as? String ?? "UNKNOWN"
    let mergeStateStatus = pr["mergeStateStatus"] as? String ?? "UNKNOWN"
    let headRefName = pr["headRefName"] as? String ?? ""
    let headRefOid = pr["headRefOid"] as? String ?? ""
    let baseRefName = pr["baseRefName"] as? String ?? "main"

    let labelNodes = (pr["labels"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
    let labels = labelNodes.compactMap { $0["name"] as? String }

    let commentNodes = (pr["comments"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
    let comments = commentNodes.map { node in
        PRComment(
            authorLogin: (node["author"] as? [String: Any])?["login"] as? String ?? "",
            body: node["body"] as? String ?? "",
            createdAt: node["createdAt"] as? String ?? ""
        )
    }

    let threadNodes = (pr["reviewThreads"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
    let reviewThreads = threadNodes.map { node in
        let innerNodes = (node["comments"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let threadComments = innerNodes.map { c in
            ReviewThreadComment(
                authorLogin: (c["author"] as? [String: Any])?["login"] as? String ?? "",
                body: c["body"] as? String ?? "",
                url: c["url"] as? String ?? ""
            )
        }
        return ReviewThread(
            isResolved: node["isResolved"] as? Bool ?? false,
            path: node["path"] as? String ?? "",
            line: node["line"] as? Int,
            comments: threadComments
        )
    }

    let commitNodes = (pr["commits"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
    let rollup = (commitNodes.first?["commit"] as? [String: Any])?["statusCheckRollup"] as? [String: Any]
    let contextNodes = (rollup?["contexts"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
    let checks: [CheckEntry] = contextNodes.compactMap { node in
        let typeName = node["__typename"] as? String ?? ""
        if typeName == "CheckRun" {
            let suite = node["checkSuite"] as? [String: Any]
            let wfRun = suite?["workflowRun"] as? [String: Any]
            let wf = wfRun?["workflow"] as? [String: Any]
            return CheckEntry(
                name: node["name"] as? String ?? "",
                workflowName: wf?["name"] as? String ?? "",
                status: node["status"] as? String ?? "",
                conclusion: node["conclusion"] as? String ?? "",
                title: node["title"] as? String ?? "",
                detailsUrl: node["detailsUrl"] as? String ?? "",
                startedAt: node["startedAt"] as? String ?? "",
                completedAt: node["completedAt"] as? String ?? ""
            )
        } else if typeName == "StatusContext" {
            let rawState = (node["state"] as? String ?? "").uppercased()
            let mappedStatus = rawState == "PENDING" ? "IN_PROGRESS" : "COMPLETED"
            let mappedConclusion = rawState == "PENDING" ? "" : rawState
            return CheckEntry(
                name: node["context"] as? String ?? "",
                workflowName: "",
                status: mappedStatus,
                conclusion: mappedConclusion,
                title: "",
                detailsUrl: node["targetUrl"] as? String ?? "",
                startedAt: node["createdAt"] as? String ?? "",
                completedAt: node["createdAt"] as? String ?? ""
            )
        }
        return nil
    }

    if !options.noFetch {
        _ = try? runProcess("git", ["fetch", "origin", baseRefName])
        if !headRefName.isEmpty {
            _ = try? runProcess("git", ["fetch", "origin", headRefName])
        }
    }

    let porcelain = (try? runProcess("git", ["worktree", "list", "--porcelain"])) ?? ""
    let worktreePath = parseWorktreePath(porcelain: porcelain, branch: headRefName, headSha: headRefOid)

    let originBase = "origin/\(baseRefName)"
    let mainHeadSha = try? runProcess("git", ["rev-parse", originBase])
        .trimmingCharacters(in: .whitespacesAndNewlines)

    var newMainCommits: [MainCommit] = []
    if mainHeadSha != nil {
        let baseRef: String?
        if let sinceMain = options.sinceMain {
            baseRef = sinceMain
        } else if let mergeBase = try? runProcess("git", ["merge-base", originBase, headRefOid])
            .trimmingCharacters(in: .whitespacesAndNewlines), !mergeBase.isEmpty {
            baseRef = mergeBase
        } else if let mergeBase = try? runProcess("git", ["merge-base", originBase, "origin/\(headRefName)"])
            .trimmingCharacters(in: .whitespacesAndNewlines), !mergeBase.isEmpty {
            baseRef = mergeBase
        } else {
            baseRef = nil
        }

        if let baseRef,
           let logOutput = try? runProcess("git", ["log", "--format=%H%x09%s", "\(baseRef)..\(originBase)"]) {
            newMainCommits = logOutput
                .split(separator: "\n")
                .compactMap { line -> MainCommit? in
                    let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { return nil }
                    return MainCommit(sha: parts[0], subject: parts[1])
                }
        }
    }

    return PRSnapshotInput(
        number: number,
        title: title,
        url: url,
        state: state,
        isDraft: isDraft,
        mergeable: mergeable,
        mergeStateStatus: mergeStateStatus,
        headRefName: headRefName,
        headRefOid: headRefOid,
        baseRefName: baseRefName,
        labels: labels,
        comments: comments,
        reviewThreads: reviewThreads,
        checks: checks,
        reviewLoopRuns: runs,
        worktreePath: worktreePath,
        mainHeadSha: mainHeadSha,
        newMainCommits: newMainCommits,
        now: Date()
    )
}

do {
    let options = try parseArgs(CommandLine.arguments)
    let repo = try resolveRepo(options.repo)
    let prNode = try fetchPRGraphQL(owner: repo.owner, name: repo.name, number: options.prNumber)
    let runs = fetchReviewLoopRuns(owner: repo.owner, name: repo.name)
    let input = try parseGraphQLPR(prNode, runs: runs, options: options)
    let report = buildReport(from: input)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

#endif
