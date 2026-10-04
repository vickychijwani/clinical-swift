import CryptoKit
import Foundation

struct Comment: Codable, Equatable {
    let path: String
    let line: Int
    let text: String
}

func normalized(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

func comments(in source: String, path: String) -> [Comment] {
    let bytes = Array(source.utf8)
    var offset = 0
    var line = 1
    var result: [Comment] = []

    func matches(_ marker: String, at index: Int) -> Bool {
        let markerBytes = Array(marker.utf8)
        return index + markerBytes.count <= bytes.count
            && bytes[index..<(index + markerBytes.count)].elementsEqual(markerBytes)
    }
    func text(_ range: Range<Int>) -> String { String(decoding: bytes[range], as: UTF8.self) }
    func append(_ value: String, at commentLine: Int) {
        let value = normalized(value)
        if !value.isEmpty { result.append(Comment(path: path, line: commentLine, text: value)) }
    }

    while offset < bytes.count {
        let start = offset
        let commentLine = line
        if matches("/*", at: offset) {
            let opening = "/*"
            let closing = "*/"
            offset += opening.utf8.count
            var depth = 1
            while offset < bytes.count && depth > 0 {
                if matches(opening, at: offset) {
                    depth += 1
                    offset += opening.utf8.count
                } else if matches(closing, at: offset) {
                    depth -= 1
                    offset += closing.utf8.count
                } else {
                    offset += 1
                }
            }
            let value = text(start..<offset).replacing(opening, with: " ").replacing(
                closing, with: " ")
            let content = value.components(separatedBy: "\n").map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("*") ? String(trimmed.dropFirst()) : trimmed
            }.joined(separator: " ")
            append(content, at: commentLine)
        } else if matches("//", at: offset) {
            offset += 2
            while offset < bytes.count && bytes[offset] == 47 { offset += 1 }
            let contentStart = offset
            while offset < bytes.count && bytes[offset] != 10 { offset += 1 }
            append(text(contentStart..<offset), at: commentLine)
        } else {
            var quoteIndex = offset
            while quoteIndex < bytes.count && bytes[quoteIndex] == 35 { quoteIndex += 1 }
            let hashes = quoteIndex - offset
            let quote = quoteIndex < bytes.count ? bytes[quoteIndex] : 0
            if quote == 34 {
                let character = String(UnicodeScalar(quote))
                let delimiter =
                    matches(String(repeating: character, count: 3), at: quoteIndex)
                    ? String(repeating: character, count: 3) : character
                let closing = delimiter + String(repeating: "#", count: hashes)
                let escape = "\\" + String(repeating: "#", count: hashes)
                offset = quoteIndex + delimiter.utf8.count
                while offset < bytes.count {
                    if matches(escape, at: offset) {
                        offset = min(bytes.count, offset + escape.utf8.count + 1)
                    } else if matches(closing, at: offset) {
                        offset += closing.utf8.count
                        break
                    } else {
                        offset += 1
                    }
                }
            } else {
                offset += 1
            }
        }
        line += bytes[start..<offset].filter { $0 == 10 }.count
    }
    return result
}

struct CheckError: Error, CustomStringConvertible {
    let description: String
}

struct CommandResult {
    let status: Int32
    let data: Data
    var text: String { String(decoding: data, as: UTF8.self) }
}

func git(_ root: URL, _ arguments: [String], check: Bool = true) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", root.path] + arguments
    process.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    // Drain while Git runs so a large source file cannot fill the pipe and stall the hook.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let result = CommandResult(status: process.terminationStatus, data: data)
    if check && result.status != 0 { throw CheckError(description: result.text) }
    return result
}

struct SourceSnapshot: Codable {
    let path: String
    let old: String
    let current: String
}

func audit(_ root: URL) throws -> (missing: [Comment], fingerprint: String) {
    let hasHead = try git(root, ["rev-parse", "--verify", "HEAD"], check: false).status == 0
    let changed = try git(
        root,
        hasHead
            ? ["diff", "HEAD", "--no-renames", "--name-only", "-z", "--", "*.swift"]
            : ["ls-files", "-z", "--", "*.swift"])
    let untracked = try git(
        root, ["ls-files", "--others", "--exclude-standard", "-z", "--", "*.swift"])
    let paths = Set((changed.text + untracked.text).split(separator: "\0").map(String.init))
        .sorted()
    var oldComments: [Comment] = []
    var currentCounts: [String: Int] = [:]
    var snapshot: [SourceSnapshot] = []
    for path in paths {
        var old = ""
        if hasHead, try git(root, ["cat-file", "-e", "HEAD:" + path], check: false).status == 0 {
            old = try git(root, ["show", "HEAD:" + path]).text
        }
        let file = root.appending(path: path)
        let current =
            FileManager.default.fileExists(atPath: file.path)
            ? try String(contentsOf: file, encoding: .utf8) : ""
        oldComments += comments(in: old, path: path)
        for comment in comments(in: current, path: path) {
            currentCounts[comment.text, default: 0] += 1
        }
        snapshot.append(SourceSnapshot(path: path, old: old, current: current))
    }
    // Match across files so a comment moved with its code is not reported as a loss.
    let missing = oldComments.filter { comment in
        guard currentCounts[comment.text, default: 0] > 0 else { return true }
        currentCounts[comment.text, default: 0] -= 1
        return false
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let digest = SHA256.hash(data: try encoder.encode(snapshot))
    let fingerprint = digest.map { String(("0" + String($0, radix: 16)).suffix(2)) }.joined()
    return (missing, fingerprint)
}

struct ReviewRecord: Codable {
    let fingerprint: String
    let reason: String
    let comments: [Comment]
}

func reviewPath(_ root: URL) throws -> URL {
    let path = try git(root, ["rev-parse", "--git-path", "codex-comment-review.json"]).text
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appending(path: path)
}

func reviewed(_ root: URL, fingerprint: String) throws -> Bool {
    let path = try reviewPath(root)
    guard let data = try? Data(contentsOf: path),
        let record = try? JSONDecoder().decode(ReviewRecord.self, from: data)
    else { return false }
    return record.fingerprint == fingerprint && !normalized(record.reason).isEmpty
}

func stopResult(_ root: URL) throws -> [String: String] {
    let result = try audit(root)
    if result.missing.isEmpty { return [:] }
    if try reviewed(root, fingerprint: result.fingerprint) { return [:] }
    let findings = result.missing.map { "- \($0.path):\($0.line): \($0.text)" }.joined(
        separator: "\n")
    return [
        "decision": "block",
        "reason": """
        Review these removed or rewritten comments before finishing:
        \(findings)
        Restore comments that still apply, or update and move them with their code.
        For intentional rewrites or obsolete comments, inspect each finding and record the reasons:
        /bin/sh .codex/hooks/stop.sh --review 'reasons'
        This records a review of this exact source change set only. Do not record a review just to clear the hook.
        Then run the check again: /bin/sh .codex/hooks/stop.sh --check
        """,
    ]
}

func runHook() -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    let isReview = args.first == "--review"
    do {
        if isReview && (args.count != 2 || normalized(args[1]).isEmpty) {
            throw CheckError(description: "Supply a non-blank review reason after --review.")
        }
        let input = isReview ? Data() : FileHandle.standardInput.readDataToEndOfFile()
        let event: [String: Any]
        if input.isEmpty {
            event = [:]
        } else if let object = try JSONSerialization.jsonObject(with: input) as? [String: Any] {
            event = object
        } else {
            throw CheckError(description: "The hook event must be a JSON object.")
        }
        if let cwd = event["cwd"], !(cwd is String) {
            throw CheckError(description: "The hook working directory must be a string.")
        }
        let cwd = URL(
            fileURLWithPath: event["cwd"] as? String ?? FileManager.default.currentDirectoryPath)
        let rootPath = try git(cwd, ["rev-parse", "--show-toplevel"]).text.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let root = URL(fileURLWithPath: rootPath)
        if isReview {
            let result = try audit(root)
            let record = ReviewRecord(
                fingerprint: result.fingerprint, reason: args[1], comments: result.missing)
            try JSONEncoder().encode(record).write(to: reviewPath(root), options: .atomic)
            print("Recorded review for \(result.missing.count) comment(s).")
        } else {
            let result = try stopResult(root)
            print(
                String(
                    decoding: try JSONSerialization.data(
                        withJSONObject: result, options: .sortedKeys), as: UTF8.self))
        }
        return 0
    } catch {
        if isReview {
            FileHandle.standardError.write(Data("Comment review failed: \(error)\n".utf8))
            return 2
        }
        let output = [
            "decision": "block", "reason": "Comment check failed. Fix and rerun it: \(error)",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: output) {
            print(String(decoding: data, as: UTF8.self))
        }
        return 0
    }
}

#if !COMMENT_HOOK_TESTS
    @main
    struct CommentHook {
        static func main() { exit(runHook()) }
    }
#endif
