import Foundation

// Match command positions and common wrappers, rather than searches for the word.
// This is a text guard for accidental direct runs, not a shell security boundary.
let invocation = try NSRegularExpression(
    pattern:
        #"(?:^|[;&|()\n])\s*(?:(?:[A-Za-z_]\w*=[^\s;&|()]+\s+)|(?:(?:[^\s\"';&|()]*/)?(?:env|xcrun|command|exec|sudo|bash|zsh|sh)\b[^\n;&|()]*?\s+))*[\"']?(?:[^\s\"';&|()]*/)?xcodebuild[\"']?(?=\s|$|[;&|()])"#
)

func blocks(_ command: String) -> Bool {
    invocation.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) != nil
}

func deny(_ reason: String) {
    let response = ["decision": "block", "reason": reason]
    let data = try! JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

if CommandLine.arguments.dropFirst().first == "--test" {
    let denied = [
        "xcodebuild test", "xcodebuild -version", "/usr/bin/xcodebuild build",
        "\"/usr/bin/xcodebuild\" test", "'xcodebuild' test", "xcrun xcodebuild test",
        "xcrun --sdk iphonesimulator xcodebuild test",
        "env DEVELOPER_DIR=/Applications/Xcode.app xcodebuild test",
        "DEVELOPER_DIR=/Applications/Xcode.app xcodebuild test",
        "command xcodebuild test", "exec xcodebuild test", "sudo xcodebuild test",
        "cd repo && xcodebuild test", "make build; xcodebuild test", "false || xcodebuild test",
        "xcodebuild test | tee log", "echo $(xcodebuild -version)",
        "sh -c 'xcodebuild test'", "zsh -lc \"xcrun xcodebuild test\"",
        "make build\nxcodebuild test",
    ]
    let allowed = [
        "make build", "make app-test ONLY_TESTING='clinical-swiftTests/TrayTests'",
        "make ui-test ONLY_TESTING='clinical-swiftUITests/TrayUITests'",
        "rg -n 'xcodebuild' Makefile", "echo xcodebuild", "cat .codex/hooks/check_xcodebuild.swift",
        "make -n ui-test", "git diff --check", "echo /usr/bin/xcodebuild",
    ]
    let failures = denied.filter { !blocks($0) } + allowed.filter { blocks($0) }
    guard failures.isEmpty else {
        for command in failures { fputs("FAIL: \(command)\n", stderr) }
        exit(1)
    }
    print("PASS: \(denied.count) blocked commands and \(allowed.count) allowed commands")
} else {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    if let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let toolInput = input["tool_input"] as? [String: Any],
        let command = toolInput["command"] as? String
    {
        if blocks(command) {
            deny(
                "Direct xcodebuild commands are blocked. Use Makefile targets with documented options, such as make app-test or make ui-test with ONLY_TESTING. Add missing Makefile options instead of bypassing the standard flags and quiet formatter."
            )
        } else {
            print("{}")
        }
    } else {
        deny(
            "The build command guard could not read tool_input.command. Check the hook input before running the command."
        )
    }
}
