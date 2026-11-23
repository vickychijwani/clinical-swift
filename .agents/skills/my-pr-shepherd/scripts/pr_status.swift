import Foundation

let trustedAuthors: Set<String> = [
    "vickychijwani",
    "clinical-pr-shepherd", "clinical-pr-shepherd[bot]",
    "clinical-antigravity", "clinical-antigravity[bot]",
    "clinical-codex", "clinical-codex[bot]",
]

// MARK: - GraphQL & Output Models

struct Nodes<T: Decodable>: Decodable { let nodes: [T] }
struct Author: Decodable { let login: String }
struct Label: Decodable { let name: String }

struct RawComment: Decodable {
    let author: Author?
    let body: String
    let createdAt: String
}

struct RawThread: Decodable {
    let isResolved: Bool
    let path: String
    let line: Int?
    let comments: Nodes<ThreadComment>
    struct ThreadComment: Decodable { let author: Author?; let body: String; let url: String }
}

struct RawCheck: Decodable {
    let __typename: String
    let name: String?
    let status: String?
    let conclusion: String?
    let title: String?
    let detailsUrl: String?
    let startedAt: String?
    let completedAt: String?
    let checkSuite: CheckSuite?
    let context: String?
    let state: String?
    let targetUrl: String?
    let createdAt: String?

    struct CheckSuite: Decodable {
        let workflowRun: WorkflowRun?
        struct WorkflowRun: Decodable {
            let workflow: Workflow?
            struct Workflow: Decodable { let name: String? }
        }
    }
}

struct RawPR: Decodable {
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
    let labels: Nodes<Label>
    let comments: Nodes<RawComment>
    let reviewThreads: Nodes<RawThread>
    let commits: Nodes<CommitNode>

    struct CommitNode: Decodable {
        let commit: Commit
        struct Commit: Decodable {
            let statusCheckRollup: Rollup?
            struct Rollup: Decodable { let contexts: Nodes<RawCheck> }
        }
    }
}

struct WorkflowRun: Codable, Equatable {
    let databaseId: Int
    let status: String
    let conclusion: String?
    let createdAt: String
    let displayTitle: String
    let url: String
}

struct Check: Codable, Equatable {
    let name: String
    let workflow: String
    let status: String
    let conclusion: String
    let title: String
    let detailsUrl: String
    let timestamp: String
}

struct Snapshot: Encodable {
    let pr: PRInfo
    let worktreePath: String?
    let trustedComments: [CommentInfo]
    let unresolvedThreads: [ThreadInfo]
    let checks: [Check]
    let reviewLoopRuns: [WorkflowRun]
    let mainHeadSha: String?
    let newMainCommits: [MainCommit]

    struct PRInfo: Encodable {
        let number: Int
        let title, url, state, mergeable, mergeStateStatus, headRefName, headRefOid, baseRefName: String
        let isDraft: Bool
        let labels: [String]
    }
    struct CommentInfo: Encodable, Equatable { let author, body, createdAt: String }
    struct ThreadInfo: Encodable, Equatable { let path: String; let line: Int?; let lastAuthor, body, url: String }
    struct MainCommit: Encodable, Equatable { let sha, subject: String }
}

// MARK: - Deterministic Sanitization

func isTrusted(_ login: String?) -> Bool {
    guard let login else { return false }
    return trustedAuthors.contains(login.lowercased())
}

func normalizeChecks(_ raw: [RawCheck]) -> [Check] {
    let items: [Check] = raw.compactMap { c in
        if c.__typename == "CheckRun" {
            return Check(
                name: c.name ?? "",
                workflow: c.checkSuite?.workflowRun?.workflow?.name ?? "",
                status: (c.status ?? "").uppercased(),
                conclusion: (c.conclusion ?? "").uppercased(),
                title: c.title ?? "",
                detailsUrl: c.detailsUrl ?? "",
                timestamp: (c.startedAt?.isEmpty == false ? c.startedAt : c.completedAt) ?? ""
            )
        }
        guard c.__typename == "StatusContext" else { return nil }
        let state = (c.state ?? "").uppercased()
        return Check(
            name: c.context ?? "",
            workflow: "",
            status: state == "PENDING" ? "IN_PROGRESS" : "COMPLETED",
            conclusion: state == "PENDING" ? "" : state,
            title: "",
            detailsUrl: c.targetUrl ?? "",
            timestamp: c.createdAt ?? ""
        )
    }

    // Keep the latest run per check. Checks API review/address runs can attach to any suite,
    // so deduplicate those by name alone.
    var latest: [String: Check] = [:]
    var order: [String] = []
    for item in items {
        let lower = item.name.lowercased()
        let isLoop = lower == "review" || lower.hasPrefix("review (") || lower == "address" || lower.hasPrefix("address (")
        let key = isLoop ? "loop::\(lower)" : "\(item.workflow.lowercased())::\(lower)"
        if let prev = latest[key] {
            if item.timestamp >= prev.timestamp { latest[key] = item }
        } else {
            latest[key] = item
            order.append(key)
        }
    }
    return order.compactMap { latest[$0] }
}

// Ignore skipped workflow runs caused by non-command PR comments.
func filterReviewLoopRuns(_ runs: [WorkflowRun], prTitle: String) -> [WorkflowRun] {
    runs.filter {
        $0.displayTitle == prTitle
            && !($0.status.lowercased() == "completed" && ($0.conclusion ?? "").lowercased() == "skipped")
    }
}

func parseWorktreePath(porcelain: String, branch: String, headSha: String) -> String? {
    let blocks = porcelain.components(separatedBy: "\n\n").map { $0.split(separator: "\n").map(String.init) }
    func path(in lines: [String]) -> String? {
        lines.first { $0.hasPrefix("worktree ") }.map { String($0.dropFirst("worktree ".count)) }
    }
    if let match = blocks.first(where: { $0.contains("branch refs/heads/\(branch)") }) {
        return path(in: match)
    }
    return blocks.first(where: { $0.contains("HEAD \(headSha)") }).flatMap(path(in:))
}

func buildSnapshot(
    pr: RawPR,
    runs: [WorkflowRun],
    worktreePath: String?,
    mainHeadSha: String?,
    newMainCommits: [Snapshot.MainCommit]
) -> Snapshot {
    let comments = pr.comments.nodes.compactMap { c -> Snapshot.CommentInfo? in
        guard isTrusted(c.author?.login) else { return nil }
        return Snapshot.CommentInfo(author: c.author!.login, body: c.body, createdAt: c.createdAt)
    }
    let threads = pr.reviewThreads.nodes.compactMap { t -> Snapshot.ThreadInfo? in
        guard !t.isResolved, let last = t.comments.nodes.filter({ isTrusted($0.author?.login) }).last else { return nil }
        return Snapshot.ThreadInfo(path: t.path, line: t.line, lastAuthor: last.author!.login, body: last.body, url: last.url)
    }
    let checks = normalizeChecks(pr.commits.nodes.first?.commit.statusCheckRollup?.contexts.nodes ?? [])
    return Snapshot(
        pr: .init(
            number: pr.number, title: pr.title, url: pr.url, state: pr.state,
            mergeable: pr.mergeable, mergeStateStatus: pr.mergeStateStatus,
            headRefName: pr.headRefName, headRefOid: pr.headRefOid, baseRefName: pr.baseRefName,
            isDraft: pr.isDraft, labels: pr.labels.nodes.map(\.name)
        ),
        worktreePath: worktreePath,
        trustedComments: comments,
        unresolvedThreads: threads,
        checks: checks,
        reviewLoopRuns: filterReviewLoopRuns(runs, prTitle: pr.title),
        mainHeadSha: mainHeadSha,
        newMainCommits: newMainCommits
    )
}

// MARK: - CLI

#if !PR_STATUS_TESTS

struct CLIError: Error, CustomStringConvertible { let description: String }

func run(_ exe: String, _ args: [String]) throws -> Data {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = [exe] + args
    p.standardInput = FileHandle.nullDevice
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    try p.run()
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        throw CLIError(description: "\(exe) failed: \(String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    return outData
}

func runText(_ exe: String, _ args: [String]) throws -> String {
    String(decoding: try run(exe, args), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

let usage = "Usage: swift pr_status.swift <pr-number> [--since-main <sha>] [--repo <owner/name>] [--no-fetch]"
let args = Array(CommandLine.arguments.dropFirst())

func option(_ flag: String) throws -> String? {
    guard let i = args.firstIndex(of: flag) else { return nil }
    guard i + 1 < args.count else { throw CLIError(description: "Missing value for \(flag). \(usage)") }
    return args[i + 1]
}

do {
    guard let prStr = args.first, let prNumber = Int(prStr), !args.contains("-h"), !args.contains("--help") else {
        throw CLIError(description: usage)
    }
    let sinceMain = try option("--since-main")
    let repoStr = try option("--repo") ?? runText("gh", ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"])
    let repoParts = repoStr.split(separator: "/").map(String.init)
    guard repoParts.count == 2 else { throw CLIError(description: "Invalid repo '\(repoStr)'.") }

    let query = """
    query($owner:String!,$name:String!,$num:Int!){
      repository(owner:$owner,name:$name){
        pullRequest(number:$num){
          number title url state isDraft mergeable mergeStateStatus headRefName headRefOid baseRefName
          labels(first:50){ nodes { name } }
          comments(last:100){ nodes { author { login } body createdAt } }
          reviewThreads(first:100){ nodes { isResolved path line comments(first:50){ nodes { author { login } body url } } } }
          commits(last:1){ nodes { commit { statusCheckRollup { contexts(first:100){ nodes {
            __typename
            ... on CheckRun { name status conclusion title detailsUrl startedAt completedAt checkSuite { workflowRun { workflow { name } } } }
            ... on StatusContext { context state targetUrl createdAt }
          } } } } } }
        }
      }
    }
    """
    struct GraphQLResponse: Decodable {
        let data: DataNode
        struct DataNode: Decodable { let repository: RepoNode }
        struct RepoNode: Decodable { let pullRequest: RawPR }
    }

    let gqlData = try run("gh", ["api", "graphql", "-f", "query=\(query)", "-F", "owner=\(repoParts[0])", "-F", "name=\(repoParts[1])", "-F", "num=\(prNumber)"])
    let pr = try JSONDecoder().decode(GraphQLResponse.self, from: gqlData).data.repository.pullRequest
    let runsData = try? run("gh", ["run", "list", "--repo", repoStr, "--workflow", "agent-review-loop.yml", "--limit", "25", "--json", "databaseId,status,conclusion,createdAt,displayTitle,url"])
    let runs = runsData.flatMap { try? JSONDecoder().decode([WorkflowRun].self, from: $0) } ?? []

    if !args.contains("--no-fetch") {
        _ = try? run("git", ["fetch", "origin", pr.baseRefName])
        _ = try? run("git", ["fetch", "origin", pr.headRefName])
    }

    let porcelain = (try? runText("git", ["worktree", "list", "--porcelain"])) ?? ""
    let worktreePath = parseWorktreePath(porcelain: porcelain, branch: pr.headRefName, headSha: pr.headRefOid)
    let originBase = "origin/\(pr.baseRefName)"
    let mainHeadSha = try? runText("git", ["rev-parse", originBase])
    let baseRef = sinceMain
        ?? (try? runText("git", ["merge-base", originBase, pr.headRefOid]))
        ?? (try? runText("git", ["merge-base", originBase, "origin/\(pr.headRefName)"]))
    let newMainCommits: [Snapshot.MainCommit] = (baseRef.flatMap { try? runText("git", ["log", "--format=%H%x09%s", "\($0)..\(originBase)"]) } ?? "")
        .split(separator: "\n")
        .compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return p.count == 2 ? Snapshot.MainCommit(sha: p[0], subject: p[1]) : nil
        }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let output = try encoder.encode(buildSnapshot(pr: pr, runs: runs, worktreePath: worktreePath, mainHeadSha: mainHeadSha, newMainCommits: newMainCommits))
    FileHandle.standardOutput.write(output + Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

#endif
