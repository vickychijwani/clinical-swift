import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Check failed") throws {
    if !condition() { throw CheckError(description: message) }
}

final class Fixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "comment hook \(UUID())")

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(root, ["init", "-q"])
        try write("App.swift", "// Keep the home-screen decision.\nlet tab = 1\n")
        try write("Sync.swift", "// Keep the pending revision.\nlet revision = 1\n")
        try commit()
    }

    func write(_ path: String, _ text: String) throws {
        try text.write(to: root.appending(path: path), atomically: true, encoding: .utf8)
    }

    func commit() throws {
        try git(root, ["add", "."])
        try git(
            root,
            [
                "-c", "user.name=Hook Test", "-c", "user.email=hook@example.test",
                "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm",
                "Fixture",
            ])
    }

    func recordReview(_ reason: String) throws {
        let result = try audit(root)
        let record = ReviewRecord(
            fingerprint: result.fingerprint, reason: reason, comments: result.missing)
        try JSONEncoder().encode(record).write(to: reviewPath(root))
    }
}

func withFixture(_ body: (Fixture) throws -> Void) throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try body(fixture)
}

func cli(_ binary: String, root: URL, args: [String] = [], input: String = "{}") throws -> (
    Int32, String
) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = args
    process.currentDirectoryURL = root
    let source = Pipe()
    let output = Pipe()
    process.standardInput = source
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    source.fileHandleForWriting.write(Data(input.utf8))
    try source.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

@main
struct CommentHookTests {
    static func main() throws {
        let binary = CommandLine.arguments[1]
        var failures = 0
        var count = 0
        func test(_ name: String, _ body: () throws -> Void) {
            count += 1
            do {
                try body()
                print("PASS \(name)")
            } catch {
                failures += 1
                print("FAIL \(name): \(error)")
            }
        }
        func texts(_ source: String) -> [String] {
            comments(in: source, path: "App.swift").map(\.text)
        }

        test("Inline comments and documentation comments") {
            try expect(
                texts("/// The home screen.\nlet tab = 1 // Keep this choice.\n") == [
                    "The home screen.", "Keep this choice.",
                ])
        }
        test("Quoted URLs are not comments") {
            try expect(texts("let url = \"https://clinic.test\" // Keep\n") == ["Keep"])
        }
        test("Raw strings are not comments") {
            try expect(texts("let text = ##\"/* text */ // text\"##\n// Keep") == ["Keep"])
        }
        test("Multiline strings are not comments") {
            try expect(texts("let text = \"\"\"\n// text\n/* text */\n\"\"\"\n// Keep") == ["Keep"])
        }
        test("Escaped quotes do not end strings") {
            try expect(texts(#"let text = "\" // text" // Keep"#) == ["Keep"])
        }
        test("Nested block comments") {
            try expect(
                texts("/* Explain\n * the invariant. /* Nested reason. */\n */") == [
                    "Explain the invariant. Nested reason."
                ])
        }
        test("Whitespace is ignored") {
            try expect(texts("// Keep   this choice.  ") == ["Keep this choice."])
        }
        test("Empty comment lines are ignored") {
            try expect(texts("///\n//\n/**/\n") == [])
        }
        test("Source line numbers are preserved") {
            try expect(
                comments(in: "\nlet text = \"\"\"\nvalue\n\"\"\"\n// Keep", path: "App.swift")
                    .first?.line == 5)
        }
        test("Clean worktree passes") {
            try withFixture { fixture in
                let result = try stopResult(fixture.root)
                try expect(result.isEmpty)
            }
        }
        test("Code-only changes pass") {
            try withFixture { fixture in
                try fixture.write("App.swift", "// Keep the home-screen decision.\nlet tab = 2\n")
                let result = try stopResult(fixture.root)
                try expect(result.isEmpty)
            }
        }
        test("Missing comment blocks") {
            try withFixture { fixture in
                try fixture.write("App.swift", "let tab = 1\n")
                let result = try stopResult(fixture.root)
                try expect(result["decision"] == "block")
                try expect(
                    result["reason"]?.contains("App.swift:1: Keep the home-screen decision.")
                        == true)
            }
        }
        test("Staged and unstaged changes are checked") {
            try withFixture { fixture in
                try fixture.write("App.swift", "let tab = 1\n")
                try git(fixture.root, ["add", "App.swift"])
                try fixture.write("Sync.swift", "let revision = 1\n")
                let result = try audit(fixture.root)
                try expect(Set(result.missing.map(\.path)) == ["App.swift", "Sync.swift"])
            }
        }
        test("Moved comments in new files pass") {
            try withFixture { fixture in
                try fixture.write("App.swift", "let tab = 1\n")
                try fixture.write("New file.swift", "// Keep the home-screen decision.\n")
                let result = try stopResult(fixture.root)
                try expect(result.isEmpty)
            }
        }
        test("Renamed files preserve comments") {
            try withFixture { fixture in
                try git(fixture.root, ["mv", "App.swift", "Renamed.swift"])
                let result = try stopResult(fixture.root)
                try expect(result.isEmpty)
            }
        }
        test("Deleted files are checked") {
            try withFixture { fixture in
                try FileManager.default.removeItem(at: fixture.root.appending(path: "Sync.swift"))
                let result = try stopResult(fixture.root)
                try expect(result["decision"] == "block")
            }
        }
        test("Duplicate comments do not hide a loss") {
            try withFixture { fixture in
                try fixture.write("App.swift", "// Keep\n// Keep\n")
                try fixture.commit()
                try fixture.write("App.swift", "// Keep\n")
                let result = try audit(fixture.root)
                try expect(result.missing.count == 1)
            }
        }
        test("Rewrites need review and review expires after code edits") {
            try withFixture { fixture in
                try fixture.write("App.swift", "// Schedule is the home screen.\nlet tab = 1\n")
                let blocked = try stopResult(fixture.root)
                try expect(blocked["decision"] == "block")
                try fixture.recordReview(
                    "Reworded the home-screen comment; its intent is preserved.")
                let passed = try stopResult(fixture.root)
                try expect(passed.isEmpty)
                try fixture.write("App.swift", "// Schedule is the home screen.\nlet tab = 2\n")
                let changed = try stopResult(fixture.root)
                try expect(changed["decision"] == "block")
            }
        }
        test("Untracked destination edits invalidate review") {
            try withFixture { fixture in
                try fixture.write("App.swift", "let tab = 1\n")
                try fixture.write("New.swift", "// Schedule is the home screen.\n")
                try fixture.recordReview("Reworded the comment in New.swift.")
                try fixture.write("New.swift", "let tab = 1\n")
                let result = try stopResult(fixture.root)
                try expect(result["decision"] == "block")
            }
        }
        test("Non-Swift changes are outside the check") {
            try withFixture { fixture in
                try fixture.write("config.toml", "# Keep\n")
                try fixture.commit()
                try fixture.write("config.toml", "name = 'Clinic'\n")
                let result = try stopResult(fixture.root)
                try expect(result.isEmpty)
            }
        }
        test("Stop continuation still requires review") {
            try withFixture { fixture in
                try fixture.write("App.swift", "let tab = 1\n")
                let result = try cli(
                    binary, root: fixture.root, input: "{\"stop_hook_active\":true}")
                try expect(result.0 == 0 && result.1.contains("\"block\""))
            }
        }
        test("Review CLI rejects blank reasons") {
            try withFixture { fixture in
                let result = try cli(binary, root: fixture.root, args: ["--review", " "])
                try expect(result.0 == 2)
            }
        }
        test("Review CLI records a valid review") {
            try withFixture { fixture in
                try fixture.write("App.swift", "// Schedule is the home screen.\nlet tab = 1\n")
                let result = try cli(
                    binary, root: fixture.root,
                    args: ["--review", "Reworded the home-screen comment."])
                try expect(result.0 == 0)
                let passed = try stopResult(fixture.root)
                try expect(passed.isEmpty)
            }
        }
        test("Malformed events produce blocking JSON") {
            try withFixture { fixture in
                for event in ["broken", "null", "[]", "{\"cwd\":null}"] {
                    let result = try cli(binary, root: fixture.root, input: event)
                    try expect(result.0 == 0 && result.1.contains("\"block\""))
                }
            }
        }
        test("New repositories have no committed baseline") {
            let root = FileManager.default.temporaryDirectory.appending(path: "new hook \(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try git(root, ["init", "-q"])
            try "// New comment\n".write(
                to: root.appending(path: "New.swift"), atomically: true, encoding: .utf8)
            try git(root, ["add", "."])
            let result = try stopResult(root)
            try expect(result.isEmpty)
        }
        print("\(count) tests, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
