import Foundation

enum BlockedSubcommand: String {
    case openurl
    case launch
    case ui

    var reason: String {
        switch self {
        case .openurl:
            return
                "Direct 'xcrun simctl openurl' commands are blocked because custom URL schemes trigger SpringBoard confirmation alerts on iOS Simulator. Use 'make run' or 'make screenshot' with LAUNCH_ARGS, or tap the UI control instead."
        case .launch:
            return
                "Direct 'xcrun simctl launch' commands are blocked. Use 'make run', 'make build-and-run', or 'make screenshot' with SIMULATOR_NAME, LAUNCH_ARGS, and APPEARANCE instead."
        case .ui:
            return
                "Direct 'xcrun simctl ui' commands are blocked. Use 'make appearance APPEARANCE=light|dark' or pass APPEARANCE=light|dark to 'make run', 'make build-and-run', or 'make screenshot' instead."
        }
    }
}

enum HookMode {
    case codex
    case antigravity

    var denyDecision: String {
        switch self {
        case .codex: "block"
        case .antigravity: "deny"
        }
    }

    var allowJSON: String {
        switch self {
        case .codex: "{}"
        case .antigravity: #"{"decision":"allow"}"#
        }
    }

    var commandFieldDescription: String {
        switch self {
        case .codex: "tool_input.command"
        case .antigravity: "toolCall.args.CommandLine"
        }
    }
}

// Match command positions and common wrappers, rather than searches for the words.
// This is a text guard for accidental direct runs, not a shell security boundary.
let invocation = try NSRegularExpression(
    pattern:
        #"(?:^|[;&|()\n])\s*(?:(?:[A-Za-z_]\w*=(?:"[^"\n]*"|'[^'\n]*'|[^\s;&|()])+\s+)|(?:[\"']?(?:[^\s\"';&|()]*/)?(?:env|xcrun|command|exec|sudo|bash|zsh|sh)\b[\"']?[^\n;&|()]*?\s+))*[\"']?(?:[^\s\"';&|()]*/)?simctl[\"']?\s+(?:--?(?:set|profiles-path)(?:=|\s+)(?:"[^"\n]*"|'[^'\n]*'|[^\s;&|()])+\s+)*[\"']?(openurl|launch|ui)[\"']?(?=\s|$|[;&|()])"#
)

func blockedSubcommand(in command: String) -> BlockedSubcommand? {
    let fullRange = NSRange(command.startIndex..., in: command)
    guard
        let match = invocation.firstMatch(in: command, range: fullRange),
        let subcommandRange = Range(match.range(at: 1), in: command)
    else {
        return nil
    }
    return BlockedSubcommand(rawValue: String(command[subcommandRange]))
}

func extractCommand(from data: Data, mode: HookMode) -> String? {
    guard let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    switch mode {
    case .codex:
        return (input["tool_input"] as? [String: Any])?["command"] as? String
    case .antigravity:
        let toolCall = input["toolCall"] as? [String: Any]
        let args = toolCall?["args"] as? [String: Any]
        return args?["CommandLine"] as? String
    }
}

func encodeDecision(_ decision: String, reason: String) -> String {
    let response = ["decision": decision, "reason": reason]
    let data = try! JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

func evaluate(payload: Data, mode: HookMode) -> String {
    guard let command = extractCommand(from: payload, mode: mode) else {
        return encodeDecision(
            mode.denyDecision,
            reason:
                "The simulator command guard could not read \(mode.commandFieldDescription). Check the hook input before running the command."
        )
    }
    if let blocked = blockedSubcommand(in: command) {
        return encodeDecision(mode.denyDecision, reason: blocked.reason)
    }
    return mode.allowJSON
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--test" {
    let denied: [(String, BlockedSubcommand)] = [
        ("xcrun simctl openurl booted clinical://schedule", .openurl),
        ("xcrun simctl openurl \"$SIM_ID\" \"clinical://schedule?date=2026-11-24\"", .openurl),
        ("xcrun simctl launch \"$SIM_ID\" in.bitehaus.clinical", .launch),
        ("xcrun simctl launch --terminate-running-process booted in.bitehaus.clinical --preview-toast", .launch),
        ("xcrun simctl ui \"$SIM_ID\" appearance light", .ui),
        ("xcrun simctl ui booted appearance", .ui),
        ("/usr/bin/xcrun simctl openurl booted clinical://schedule", .openurl),
        ("\"/usr/bin/xcrun\" 'simctl' \"launch\" booted in.bitehaus.clinical", .launch),
        ("xcrun --sdk iphonesimulator simctl ui booted appearance dark", .ui),
        ("xcrun simctl --set /tmp/sims launch booted in.bitehaus.clinical", .launch),
        ("xcrun simctl --set \"/tmp/my sims\" ui booted appearance light", .ui),
        ("xcrun simctl --profiles-path=/tmp/p openurl booted clinical://schedule", .openurl),
        ("simctl launch booted in.bitehaus.clinical", .launch),
        ("/Applications/Xcode.app/Contents/Developer/usr/bin/simctl ui booted appearance light", .ui),
        ("SIMCTL_CHILD_FOO=1 xcrun simctl launch booted in.bitehaus.clinical", .launch),
        ("SIMCTL_CHILD_FOO=\"a b\" xcrun simctl launch booted in.bitehaus.clinical", .launch),
        ("env DEVELOPER_DIR=/Applications/Xcode.app xcrun simctl ui booted appearance light", .ui),
        ("command xcrun simctl openurl booted clinical://schedule", .openurl),
        ("exec xcrun simctl launch booted in.bitehaus.clinical", .launch),
        ("sudo xcrun simctl ui booted appearance dark", .ui),
        ("SIM_ID=\"$(make -s sim-id)\" && xcrun simctl launch \"$SIM_ID\" in.bitehaus.clinical", .launch),
        ("make boot; xcrun simctl ui booted appearance light", .ui),
        ("false || xcrun simctl openurl booted clinical://schedule", .openurl),
        ("xcrun simctl ui booted appearance | cat", .ui),
        ("echo $(xcrun simctl ui booted appearance)", .ui),
        ("sh -c 'xcrun simctl openurl booted clinical://schedule'", .openurl),
        ("zsh -lc \"xcrun simctl launch booted in.bitehaus.clinical\"", .launch),
        ("SIM_ID=123\nxcrun simctl ui \"$SIM_ID\" appearance light", .ui),
    ]
    let allowed = [
        "make run SIMULATOR_NAME='fix-card' LAUNCH_ARGS='--preview-toast' APPEARANCE=light",
        "make build-and-run SIMULATOR_NAME='fix-card' LAUNCH_ARGS='--preview-toast'",
        "make screenshot SIMULATOR_NAME='fix-card' APPEARANCE=light OUT=build/after.png",
        "make appearance SIMULATOR_NAME='fix-card' APPEARANCE=dark",
        "make sim-id SIMULATOR_NAME='fix-card'",
        "xcrun simctl list devices --json",
        "xcrun simctl boot \"$SIM_ID\"",
        "xcrun simctl bootstatus \"$SIM_ID\" -b",
        "xcrun simctl shutdown \"$SIM_ID\"",
        "xcrun simctl install \"$SIM_ID\" build/app.app",
        "xcrun simctl uninstall \"$SIM_ID\" in.bitehaus.clinical",
        "xcrun simctl terminate \"$SIM_ID\" in.bitehaus.clinical",
        "xcrun simctl get_app_container \"$SIM_ID\" in.bitehaus.clinical groups",
        "xcrun simctl io \"$SIM_ID\" screenshot build/after.png",
        "xcrun simctl io \"$SIM_ID\" screenshot /tmp/ui",
        "xcrun simctl io \"$SIM_ID\" screenshot /tmp/launch.png",
        "xcrun simctl create ui com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0",
        "xcrun simctl status_bar \"$SIM_ID\" override --time 9:41",
        "xcrun simctl list | grep ui",
        "rg -n 'xcrun simctl openurl' .codex",
        "echo 'xcrun simctl launch booted in.bitehaus.clinical'",
        "cat .codex/hooks/check_simctl.swift",
        "git diff --check",
    ]

    var failures: [String] = []
    for (command, expected) in denied {
        let actual = blockedSubcommand(in: command)
        if actual != expected {
            failures.append("Expected \(expected.rawValue), got \(actual?.rawValue ?? "allow"): \(command)")
        }
    }
    for command in allowed {
        if let actual = blockedSubcommand(in: command) {
            failures.append("Expected allow, got \(actual.rawValue): \(command)")
        }
    }

    // Verify both Codex and Antigravity JSON contracts.
    let codexDeny = evaluate(
        payload: Data(#"{"tool_input":{"command":"xcrun simctl openurl booted clinical://schedule"}}"#.utf8),
        mode: .codex
    )
    if !codexDeny.contains(#""decision":"block""#) || !codexDeny.contains("openurl") {
        failures.append("Codex deny contract failed: \(codexDeny)")
    }
    let codexAllow = evaluate(
        payload: Data(#"{"tool_input":{"command":"make screenshot APPEARANCE=light"}}"#.utf8),
        mode: .codex
    )
    if codexAllow != "{}" {
        failures.append("Codex allow contract failed: \(codexAllow)")
    }
    let codexInvalid = evaluate(payload: Data("not-json".utf8), mode: .codex)
    if !codexInvalid.contains(#""decision":"block""#) {
        failures.append("Codex fail-closed contract failed: \(codexInvalid)")
    }

    let agyDeny = evaluate(
        payload: Data(#"{"toolCall":{"name":"run_command","args":{"CommandLine":"xcrun simctl ui booted appearance light"}}}"#.utf8),
        mode: .antigravity
    )
    if !agyDeny.contains(#""decision":"deny""#) || !agyDeny.contains("make appearance") {
        failures.append("Antigravity deny contract failed: \(agyDeny)")
    }
    let agyAllow = evaluate(
        payload: Data(#"{"toolCall":{"name":"run_command","args":{"CommandLine":"make run LAUNCH_ARGS='--preview-toast'"}}}"#.utf8),
        mode: .antigravity
    )
    if agyAllow != #"{"decision":"allow"}"# {
        failures.append("Antigravity allow contract failed: \(agyAllow)")
    }
    let agyInvalid = evaluate(payload: Data("{}".utf8), mode: .antigravity)
    if !agyInvalid.contains(#""decision":"deny""#) {
        failures.append("Antigravity fail-closed contract failed: \(agyInvalid)")
    }

    guard failures.isEmpty else {
        for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
        exit(1)
    }
    print("PASS: \(denied.count) blocked commands, \(allowed.count) allowed commands, and 6 JSON contract checks")
} else {
    let mode: HookMode = arguments.contains("--antigravity") ? .antigravity : .codex
    let data = FileHandle.standardInput.readDataToEndOfFile()
    print(evaluate(payload: data, mode: mode))
}
