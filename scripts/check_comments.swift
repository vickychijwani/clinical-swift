import Foundation

struct Comment: Equatable {
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

@discardableResult
func git(_ root: URL, _ arguments: [String], check: Bool = true) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", root.path] + arguments
    process.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    // Drain while Git runs so a large source file cannot fill the pipe and stall execution.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let result = CommandResult(status: process.terminationStatus, data: data)
    if check && result.status != 0 { throw CheckError(description: result.text) }
    return result
}

func resolveBaseline(_ root: URL, baseRef: String?) throws -> String? {
    let hasHead = try git(root, ["rev-parse", "--verify", "HEAD"], check: false).status == 0
    guard let baseRef else { return hasHead ? "HEAD" : nil }
    // Use the merge base so unrelated commits merged onto the base branch are not reported as losses.
    if hasHead {
        let mergeBase = try git(root, ["merge-base", "HEAD", baseRef], check: false)
        if mergeBase.status == 0 {
            return mergeBase.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return try git(root, ["rev-parse", "--verify", "\(baseRef)^{commit}"]).text
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func missingComments(_ root: URL, baseRef: String? = nil) throws -> [Comment] {
    let baseline = try resolveBaseline(root, baseRef: baseRef)
    let changed = try git(
        root,
        baseline.map { ["diff", $0, "--no-renames", "--name-only", "-z", "--", "*.swift"] }
            ?? ["ls-files", "-z", "--", "*.swift"])
    let untracked = try git(
        root, ["ls-files", "--others", "--exclude-standard", "-z", "--", "*.swift"])
    let paths = Set((changed.text + untracked.text).split(separator: "\0").map(String.init))
        .sorted()
    var oldComments: [Comment] = []
    var currentCounts: [String: Int] = [:]
    for path in paths {
        var old = ""
        if let baseline,
            try git(root, ["cat-file", "-e", "\(baseline):\(path)"], check: false).status == 0
        {
            old = try git(root, ["show", "\(baseline):\(path)"]).text
        }
        let file = root.appending(path: path)
        let current =
            FileManager.default.fileExists(atPath: file.path)
            ? try String(contentsOf: file, encoding: .utf8) : ""
        oldComments += comments(in: old, path: path)
        for comment in comments(in: current, path: path) {
            currentCounts[comment.text, default: 0] += 1
        }
    }
    // Match across files so a comment moved with its code is not reported as a loss.
    return oldComments.filter { comment in
        guard currentCounts[comment.text, default: 0] > 0 else { return true }
        currentCounts[comment.text, default: 0] -= 1
        return false
    }
}

func runCLI() {
    let args = Array(CommandLine.arguments.dropFirst())
    do {
        let baseRef: String?
        if args.isEmpty {
            baseRef = nil
        } else if args.count == 2 && args[0] == "--base" && !normalized(args[1]).isEmpty {
            baseRef = args[1]
        } else {
            throw CheckError(
                description: "Usage: swift scripts/check_comments.swift [--base <ref>]")
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let rootPath = try git(cwd, ["rev-parse", "--show-toplevel"]).text.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let missing = try missingComments(URL(fileURLWithPath: rootPath), baseRef: baseRef)
        if missing.isEmpty {
            print("No removed or rewritten Swift comments.")
            return
        }
        print("Removed or rewritten Swift comments:")
        for comment in missing {
            print("- \(comment.path):\(comment.line): \(comment.text)")
        }
        print("Restore comments that still apply, or update and move them with their code.")
        print("Ignore intentional rewrites and obsolete comments.")
    } catch {
        FileHandle.standardError.write(Data("Comment check failed: \(error)\n".utf8))
        exit(1)
    }
}

#if !SCRIPT_TESTS
    let _ = runCLI()
#endif
