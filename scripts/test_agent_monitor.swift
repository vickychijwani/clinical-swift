import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw TestFailure(description: message)
    }
}

private func testCleanShellCommandTitle() throws {
    try expect(
        cleanShellCommandTitle("/bin/zsh -lc 'cat .agents/skills/my-review/SKILL.md'")
            == "cat .agents/skills/my-review/SKILL.md",
        "Expected zsh -lc wrapper stripped"
    )
    try expect(
        cleanShellCommandTitle("git status\ngit diff --stat") == "git status ; git diff --stat",
        "Expected multiline commands collapsed cleanly"
    )
}

private func testCodexExecJSONParsing() throws {
    let stream = """
        {"type":"thread.started","thread_id":"thread-123"}
        {"type":"item.completed","item":{"id":"item_0","type":"error","message":"`--dangerously-bypass-hook-trust` is enabled."}}
        {"type":"turn.started"}
        {"type":"item.completed","item":{"id":"item_1","type":"reasoning","text":"Checking PR diff"}}
        {"type":"item.started","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc 'git status'","aggregated_output":"","exit_code":null,"status":"in_progress"}}
        {"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc 'git status'","aggregated_output":"clean","exit_code":0,"status":"completed"}}
        {"type":"item.completed","item":{"id":"item_3","type":"file_change","changes":[{"path":"Foo.swift","kind":"update"}],"status":"completed"}}
        {"type":"item.completed","item":{"id":"item_4","type":"agent_message","text":"Posted review."}}
        {"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":400,"output_tokens":50}}
        """

    let parsed = parseAgentStream(text: stream)
    try expect(parsed.sessionID == "thread-123", "Expected thread_id")
    try expect(
        parsed.events.count == 5, "Expected item_2 upserted in place, got \(parsed.events.count)")
    try expect(parsed.events[0].kind == "notice", "Expected hook bypass warning as notice")
    try expect(parsed.events[1].kind == "reasoning", "Expected reasoning event")
    try expect(parsed.events[2].kind == "command", "Expected command event")
    try expect(parsed.events[2].title == "$ git status", "Expected cleaned command title")
    try expect(parsed.events[2].status == "completed", "Expected command completed")
    try expect(parsed.events[2].output == "clean", "Expected command output")
    try expect(parsed.events[2].exitCode == 0, "Expected exit code 0")
    try expect(parsed.events[3].kind == "file_change", "Expected file_change event")
    try expect(parsed.events[4].kind == "message", "Expected message event")
    try expect(parsed.usage.inputTokens == 1000, "Expected input tokens")
    try expect(parsed.usage.cachedInputTokens == 400, "Expected cached tokens")
    try expect(parsed.usage.outputTokens == 50, "Expected output tokens")
}

private func testAgyStreamJSONParsing() throws {
    let stream = """
        warning: --mode auto is not available for this account
        {"event":"init","conversation_id":"conv-456","init":{"model":"claude-opus-5-5","cwd":"/tmp/pr"}}
        {"event":"step_update","step_update":{"conversation_id":"conv-456","step_index":0,"state":"DONE","step_type":"user_input"}}
        {"event":"step_update","step_update":{"conversation_id":"conv-456","step_index":1,"state":"DONE","step_type":"agent_response","duration_seconds":2.5,"usage":{"input_tokens":100,"output_tokens":20,"thinking_tokens":15,"cache_read_tokens":50}}}
        {"event":"step_update","step_update":{"conversation_id":"conv-456","step_index":2,"state":"ACTIVE","step_type":"tool","tool_name":"run_command","tool_info":{"name":"run_command","parameters":{"CommandLine":"make test"}}}}
        {"event":"step_update","step_update":{"conversation_id":"conv-456","step_index":2,"state":"DONE","step_type":"tool","tool_name":"run_command","duration_seconds":1.2,"tool_info":{"name":"run_command","parameters":{"CommandLine":"make test"},"output":"PASS"}}}
        {"event":"step_update","step_update":{"conversation_id":"conv-456","step_index":3,"state":"ACTIVE","step_type":"agent_response","text_delta":"Fixed "}}
        {"event":"step_update","step_update":{"conversation_id":"conv-456","step_index":3,"state":"DONE","step_type":"agent_response","text_delta":"issue.","duration_seconds":0.8,"usage":{"input_tokens":200,"output_tokens":30,"thinking_tokens":5,"cache_read_tokens":100}}}
        {"event":"result","result":{"conversation_id":"conv-456","status":"SUCCESS","response":"Fixed issue.","duration_seconds":4.5,"num_turns":1,"usage":{"input_tokens":300,"output_tokens":50,"thinking_tokens":20,"cache_read_tokens":150}}}
        """

    let parsed = parseAgentStream(text: stream)
    try expect(parsed.sessionID == "conv-456", "Expected conversation_id")
    try expect(parsed.model == "claude-opus-5-5", "Expected model from agy init event")
    try expect(parsed.events.count == 4, "Expected notice + reasoning + tool + message")
    try expect(parsed.events[0].kind == "notice", "Expected warning notice")
    try expect(parsed.events[1].kind == "reasoning", "Expected silent thinking summary")
    try expect(parsed.events[2].kind == "command", "Expected run_command mapped to command")
    try expect(parsed.events[2].status == "completed", "Expected tool completed")
    try expect(parsed.events[2].output == "PASS", "Expected tool output")
    try expect(parsed.events[3].kind == "message", "Expected message")
    try expect(parsed.events[3].text == "Fixed issue.", "Expected text deltas concatenated")
    try expect(parsed.usage.inputTokens == 300, "Expected authoritative input tokens")
    try expect(parsed.usage.thinkingTokens == 20, "Expected authoritative thinking tokens")
    try expect(parsed.resultStatus == "SUCCESS", "Expected SUCCESS result")

    let errorStream = """
        Error: authentication required. Run 'agy' to log in, then retry.
        {"event":"result","result":{"conversation_id":"","status":"ERROR","error":"authentication failed or timed out"}}
        """
    let errorParsed = parseAgentStream(text: errorStream)
    try expect(errorParsed.events.contains { $0.kind == "error" }, "Expected auth error event")
    try expect(
        errorParsed.resultError == "authentication failed or timed out", "Expected resultError")
}

private func testAgyTranscriptParsing() throws {
    let transcript = """
        {"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-11-19T08:09:55Z","content":"<USER_REQUEST>\\nAddress review comments on PR #33 in vickychijwani/clinical-swift\\n</USER_REQUEST>"}
        {"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-19T08:09:56Z","model":"gemini-4-hydrogen-high","input_tokens":1000,"cache_read_tokens":200,"output_tokens":50,"thinking":"Inspecting review threads.","tool_calls":[{"name":"run_command","args":{"CommandLine":"\\"git status -sb\\"","toolSummary":"\\"Check git status\\""}}]}
        {"step_index":2,"source":"MODEL","type":"GENERIC","status":"DONE","created_at":"2026-11-19T08:09:57Z","content":"Command exited with code 0.\\n\\n## overlay_toast_widget"}
        {"step_index":3,"source":"SYSTEM","type":"ERROR_MESSAGE","status":"DONE","created_at":"2026-11-19T08:10:00Z","error":"API error (attempt 1): 503"}
        {"step_index":4,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-19T08:10:05Z","model":"gemini-4-hydrogen-high","input_tokens":500,"cache_read_tokens":100,"output_tokens":40,"content":"Addressed both comments."}
        """

    let parsed = parseAgentStream(text: transcript)
    try expect(parsed.model == "gemini-4-hydrogen-high", "Expected model from transcript")
    try expect(
        parsed.prompt == "Address review comments on PR #33 in vickychijwani/clinical-swift",
        "Expected extracted USER_REQUEST prompt"
    )
    try expect(parsed.events.count == 4, "Expected thinking + command + error + message")
    try expect(parsed.events[0].kind == "reasoning", "Expected thinking block")
    try expect(parsed.events[1].kind == "command", "Expected run_command mapped to command")
    try expect(
        parsed.events[1].title == "Check git status · $ git status -sb",
        "Expected unquoted tool summary + command"
    )
    try expect(parsed.events[1].status == "completed", "Expected GENERIC output paired to tool")
    try expect(parsed.events[1].exitCode == 0, "Expected exit code 0 parsed from output")
    try expect(parsed.events[2].kind == "error", "Expected ERROR_MESSAGE mapped to error")
    try expect(parsed.events[3].kind == "message", "Expected final assistant message")
    try expect(parsed.usage.inputTokens == 1500, "Expected summed input tokens")
}

private func testSnapshotDiscoveryAndAgyEnrichment(in root: URL) throws {
    let monitorDir = root.appending(path: "monitor", directoryHint: .isDirectory)
    let runDir = monitorDir.appending(path: "runs/777", directoryHint: .isDirectory)
    let agyBrainDir = root.appending(path: "agy-brain", directoryHint: .isDirectory)
    let opusLogs = agyBrainDir.appending(
        path: "opus-conv/.system_generated/logs", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: opusLogs, withIntermediateDirectories: true)

    let solStreamFile = runDir.appending(path: "review-sol.jsonl")
    try """
    {"type":"thread.started","thread_id":"recorded-thread"}
    {"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"Looking at diff"}}
    """.write(to: solStreamFile, atomically: true, encoding: .utf8)

    let opusStreamFile = runDir.appending(path: "review-opus.jsonl")
    try """
    {"event":"init","conversation_id":"opus-conv","init":{"model":"claude-opus-5-5","cwd":"/tmp/pr-opus"}}
    {"event":"result","result":{"conversation_id":"opus-conv","status":"SUCCESS","response":"Done."}}
    """.write(to: opusStreamFile, atomically: true, encoding: .utf8)

    try """
    {"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-11-19T08:00:11Z","content":"<USER_REQUEST>\\nReview PR #33\\n</USER_REQUEST>"}
    {"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-19T08:00:15Z","model":"claude-opus-5-5","thinking":"Checking diff carefully.","content":"Done."}
    """.write(
        to: opusLogs.appending(path: "transcript.jsonl"), atomically: true, encoding: .utf8)

    let runJSON = """
        {
          "runID": "777",
          "kind": "review-loop",
          "prNumber": 33,
          "prBranch": "overlay_toast_widget",
          "prHeadSHA": "abc1234",
          "repository": "vickychijwani/clinical-swift",
          "runURL": "https://github.com/vickychijwani/clinical-swift/actions/runs/777",
          "createdAt": "2026-11-19T08:00:00Z",
          "updatedAt": "2026-11-19T08:01:00Z"
        }
        """
    try runJSON.write(to: runDir.appending(path: "run.json"), atomically: true, encoding: .utf8)

    let reviewSolJSON = """
        {
          "phase": "review-sol",
          "harness": "codex",
          "botLogin": "clinical-codex[bot]",
          "model": "gpt-6.1-sol",
          "effort": "high",
          "worktreePath": "/tmp/pr-sol",
          "prompt": "Review PR #33",
          "streamFile": "\(solStreamFile.path)",
          "status": "running",
          "startedAt": "2026-11-19T08:00:10Z",
          "updatedAt": "2026-11-19T08:01:00Z"
        }
        """
    try reviewSolJSON.write(
        to: runDir.appending(path: "review-sol.json"), atomically: true, encoding: .utf8)

    let reviewOpusJSON = """
        {
          "phase": "review-opus",
          "harness": "antigravity",
          "botLogin": "clinical-antigravity[bot]",
          "model": "claude-opus-5-5",
          "effort": "high",
          "worktreePath": "/tmp/pr-opus",
          "prompt": "Review PR #33",
          "streamFile": "\(opusStreamFile.path)",
          "status": "completed",
          "conclusion": "success",
          "startedAt": "2026-11-19T08:00:10Z",
          "completedAt": "2026-11-19T08:00:50Z",
          "updatedAt": "2026-11-19T08:00:50Z"
        }
        """
    try reviewOpusJSON.write(
        to: runDir.appending(path: "review-opus.json"), atomically: true, encoding: .utf8)

    let addressJSON = """
        {
          "phase": "address",
          "harness": "antigravity",
          "botLogin": "clinical-antigravity[bot]",
          "model": "gemini-4-neon",
          "effort": "high",
          "status": "queued",
          "updatedAt": "2026-11-19T08:00:05Z"
        }
        """
    try addressJSON.write(
        to: runDir.appending(path: "address.json"), atomically: true, encoding: .utf8)

    // Legacy review.json should be ignored.
    let legacyReviewJSON = """
        {
          "phase": "review",
          "harness": "codex",
          "status": "completed",
          "conclusion": "success",
          "updatedAt": "2026-11-19T07:59:00Z"
        }
        """
    try legacyReviewJSON.write(
        to: runDir.appending(path: "review.json"), atomically: true, encoding: .utf8)

    let snapshot = loadMonitorSnapshot(
        monitorDirectory: monitorDir.path,
        agyBrainDirectory: agyBrainDir.path
    )
    try expect(snapshot.runs.count == 1, "Expected 1 workflow run")
    try expect(snapshot.runs[0].runID == "777", "Expected live workflow run")
    try expect(
        snapshot.runs[0].phases.map(\.phase) == ["review-sol", "review-opus", "address"],
        "Expected ordered multi-reviewer phases without legacy review.json"
    )
    try expect(
        snapshot.runs[0].phases[1].model == "claude-opus-5-5",
        "Expected opus review phase model"
    )
    try expect(
        snapshot.runs[0].phases[1].events.contains {
            $0.kind == "reasoning" && $0.text == "Checking diff carefully."
        },
        "Expected Antigravity phase enriched with thinking text from transcript"
    )
}

@main
struct AgentMonitorTests {
    static func main() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appending(
            path: "agent-monitor-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try testCleanShellCommandTitle()
        try testCodexExecJSONParsing()
        try testAgyStreamJSONParsing()
        try testAgyTranscriptParsing()
        try testSnapshotDiscoveryAndAgyEnrichment(in: tempRoot)
        print("PASS agent monitor unit and integration tests")
    }
}
