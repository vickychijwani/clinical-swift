import Foundation

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "Check failed") throws
{
    if !(try condition()) { throw CheckError(description: message) }
}

final class Fixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "comment check \(UUID())")

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

    func commit(_ message: String = "Fixture") throws {
        try git(root, ["add", "."])
        try git(
            root,
            [
                "-c", "user.name=Comment Test", "-c", "user.email=comment@example.test",
                "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm",
                message,
            ])
    }
}

func withFixture(_ body: (Fixture) throws -> Void) throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try body(fixture)
}

func cli(_ binary: String, root: URL, args: [String] = []) throws -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = args
    process.currentDirectoryURL = root
    process.standardInput = FileHandle.nullDevice
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

@main
struct CommentCheckTests {
    static func main() throws {
        let binary = ProcessInfo.processInfo.environment["SCRIPT_CLI_BIN"]
        var failures = 0
        var count = 0
        func test(_ name: String, _ body: () throws -> Void) {
            count += 1
            do {
                try body()
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
                try expect(try missingComments(fixture.root).isEmpty)
            }
        }
        test("Code-only changes pass") {
            try withFixture { fixture in
                try fixture.write("App.swift", "// Keep the home-screen decision.\nlet tab = 2\n")
                try expect(try missingComments(fixture.root).isEmpty)
            }
        }
        test("Missing comment is reported") {
            try withFixture { fixture in
                try fixture.write("App.swift", "let tab = 1\n")
                let result = try missingComments(fixture.root)
                try expect(
                    result == [
                        Comment(path: "App.swift", line: 1, text: "Keep the home-screen decision.")
                    ])
            }
        }
        test("Staged and unstaged changes are checked") {
            try withFixture { fixture in
                try fixture.write("App.swift", "let tab = 1\n")
                try git(fixture.root, ["add", "App.swift"])
                try fixture.write("Sync.swift", "let revision = 1\n")
                let result = try missingComments(fixture.root)
                try expect(Set(result.map(\.path)) == ["App.swift", "Sync.swift"])
            }
        }
        test("Moved comments in new files pass") {
            try withFixture { fixture in
                try fixture.write("App.swift", "let tab = 1\n")
                try fixture.write("New file.swift", "// Keep the home-screen decision.\n")
                try expect(try missingComments(fixture.root).isEmpty)
            }
        }
        test("Renamed files preserve comments") {
            try withFixture { fixture in
                try git(fixture.root, ["mv", "App.swift", "Renamed.swift"])
                try expect(try missingComments(fixture.root).isEmpty)
            }
        }
        test("Deleted files are checked") {
            try withFixture { fixture in
                try FileManager.default.removeItem(at: fixture.root.appending(path: "Sync.swift"))
                let result = try missingComments(fixture.root)
                try expect(result.map(\.path) == ["Sync.swift"])
            }
        }
        test("Duplicate comments do not hide a loss") {
            try withFixture { fixture in
                try fixture.write("App.swift", "// Keep\n// Keep\n")
                try fixture.commit()
                try fixture.write("App.swift", "// Keep\n")
                let result = try missingComments(fixture.root)
                try expect(result.count == 1)
            }
        }
        test("Non-Swift changes are outside the check") {
            try withFixture { fixture in
                try fixture.write("config.toml", "# Keep\n")
                try fixture.commit()
                try fixture.write("config.toml", "name = 'Clinic'\n")
                try expect(try missingComments(fixture.root).isEmpty)
            }
        }
        test("Base ref checks committed branch changes and ignores diverged base commits") {
            try withFixture { fixture in
                let defaultBranch = try git(fixture.root, ["branch", "--show-current"]).text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                try git(fixture.root, ["checkout", "-qb", "feature"])
                try fixture.write("App.swift", "let tab = 2\n")
                try fixture.commit("Drop comment on feature")

                // Advance the base branch with an unrelated comment so merge-base ignores it.
                try git(fixture.root, ["checkout", "-q", defaultBranch])
                try fixture.write("MainOnly.swift", "// Added later on main.\nlet mainOnly = 1\n")
                try fixture.commit("Advance main")

                try git(fixture.root, ["checkout", "-q", "feature"])
                let result = try missingComments(fixture.root, baseRef: defaultBranch)
                try expect(
                    result == [
                        Comment(path: "App.swift", line: 1, text: "Keep the home-screen decision.")
                    ])
            }
        }
        test("New repositories have no committed baseline") {
            let root = FileManager.default.temporaryDirectory.appending(path: "new check \(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try git(root, ["init", "-q"])
            try "// New comment\n".write(
                to: root.appending(path: "New.swift"), atomically: true, encoding: .utf8)
            try git(root, ["add", "."])
            try expect(try missingComments(root).isEmpty)
        }
        if let binary {
            test("CLI reports findings cleanly and rejects invalid arguments") {
                try withFixture { fixture in
                    let clean = try cli(binary, root: fixture.root)
                    try expect(clean.0 == 0 && clean.1.contains("No removed or rewritten"))
                    try fixture.write("App.swift", "let tab = 1\n")
                    let reported = try cli(binary, root: fixture.root)
                    try expect(
                        reported.0 == 0
                            && reported.1.contains(
                                "- App.swift:1: Keep the home-screen decision.")
                    )
                    let invalid = try cli(binary, root: fixture.root, args: ["--unknown"])
                    try expect(invalid.0 == 1)
                }
            }
        }
        if failures == 0 {
            print("PASS check_comments (\(count) checks)")
        } else {
            print("FAIL check_comments (\(failures) of \(count) failed)")
            exit(1)
        }
    }
}
