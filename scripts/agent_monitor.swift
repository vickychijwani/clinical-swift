import Foundation
import Network

// MARK: - Models

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
    let phase: String
    let harness: String?
    let botLogin: String?
    let model: String?
    let effort: String?
    let worktreePath: String?
    let prompt: String?
    let streamFile: String?
    let status: String
    let conclusion: String?
    let startedAt: String?
    let completedAt: String?
    let updatedAt: String
}

struct TokenUsageSummary: Codable, Equatable {
    var inputTokens: Int = 0
    var cachedInputTokens: Int = 0
    var outputTokens: Int = 0
    var thinkingTokens: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens
    }
}

struct MonitorEvent: Codable, Equatable {
    let id: String
    let kind: String
    var status: String
    var title: String?
    var text: String?
    var output: String?
    var exitCode: Int?
    var durationSeconds: Double?
    var timestamp: String?
}

struct ParsedPhaseStream: Codable, Equatable {
    var sessionID: String?
    var model: String?
    var prompt: String?
    var events: [MonitorEvent]
    var usage: TokenUsageSummary
    var resultStatus: String?
    var resultError: String?
}

struct MonitorPhaseView: Codable, Equatable {
    let phase: String
    let label: String
    let harness: String?
    let botLogin: String?
    let model: String?
    let effort: String?
    let worktreePath: String?
    let prompt: String?
    let status: String
    let conclusion: String?
    let startedAt: String?
    let completedAt: String?
    let updatedAt: String
    let sessionID: String?
    let usage: TokenUsageSummary
    let resultStatus: String?
    let resultError: String?
    let events: [MonitorEvent]
}

struct MonitorRunView: Codable, Equatable {
    let runID: String
    let kind: String
    let source: String
    let prNumber: Int?
    let prBranch: String?
    let prHeadSHA: String?
    let repository: String?
    let runURL: String?
    let createdAt: String
    let updatedAt: String
    let isLive: Bool
    let phases: [MonitorPhaseView]
}

struct MonitorSnapshot: Codable, Equatable {
    let generatedAt: String
    let runs: [MonitorRunView]
}

// MARK: - Helpers

private func stripANSI(_ input: String) -> String {
    var result = ""
    var index = input.startIndex
    while index < input.endIndex {
        let ch = input[index]
        if ch == "\u{001B}" {
            let next = input.index(after: index)
            if next < input.endIndex, input[next] == "[" {
                var cursor = input.index(after: next)
                while cursor < input.endIndex {
                    let scalar = input[cursor].unicodeScalars.first?.value ?? 0
                    if scalar >= 0x40 && scalar <= 0x7E {
                        index = input.index(after: cursor)
                        break
                    }
                    cursor = input.index(after: cursor)
                }
                if cursor == input.endIndex {
                    break
                }
                continue
            }
        }
        result.append(ch)
        index = input.index(after: index)
    }
    return result
}

private func parseJSONObject(_ line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return nil
    }
    return object
}

private func intValue(_ value: Any?) -> Int? {
    if let number = value as? NSNumber {
        return number.intValue
    }
    if let text = value as? String {
        return Int(text)
    }
    return nil
}

private func doubleValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    if let text = value as? String {
        return Double(text)
    }
    return nil
}

private func stringValue(_ value: Any?) -> String? {
    if let text = value as? String {
        return text
    }
    return nil
}

private func decodePossiblyQuotedString(_ raw: Any?) -> String? {
    guard let text = raw as? String else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""),
        let data = trimmed.data(using: .utf8),
        let decoded = try? JSONDecoder().decode(String.self, from: data)
    {
        return decoded
    }
    return text
}

private func prettyJSONString(_ value: Any?) -> String? {
    guard let value, !(value is NSNull) else { return nil }
    if let text = value as? String {
        return decodePossiblyQuotedString(text)
    }
    if let dict = value as? [String: Any] {
        var cleaned: [String: Any] = [:]
        for (k, v) in dict {
            if let str = v as? String, let unquoted = decodePossiblyQuotedString(str) {
                cleaned[k] = unquoted
            } else {
                cleaned[k] = v
            }
        }
        if JSONSerialization.isValidJSONObject(cleaned),
            let data = try? JSONSerialization.data(
                withJSONObject: cleaned, options: [.prettyPrinted, .sortedKeys])
        {
            return String(decoding: data, as: UTF8.self)
        }
    }
    guard JSONSerialization.isValidJSONObject(value),
        let data = try? JSONSerialization.data(
            withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    else {
        return String(describing: value)
    }
    return String(decoding: data, as: UTF8.self)
}

/// Strips `/bin/zsh -lc ...` shell wrappers so command headers stay compact and readable.
func cleanShellCommandTitle(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in ["/bin/zsh -lc ", "/bin/bash -lc ", "zsh -lc ", "bash -lc "] {
        if text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if (text.hasPrefix("'") && text.hasSuffix("'"))
                || (text.hasPrefix("\"") && text.hasSuffix("\""))
            {
                if text.count >= 2 {
                    text = String(text.dropFirst().dropLast())
                }
            }
            break
        }
    }
    let singleLine = text
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: " ; ")
    return singleLine.isEmpty ? raw : singleLine
}

private func shortenPath(_ path: String) -> String {
    for marker in ["/clinical-swift/", "/worktrees/"] {
        if let range = path.range(of: marker) {
            return String(path[range.upperBound...])
        }
    }
    return path
}

private func formatToolSummary(name: String, parameters: [String: Any]?) -> String {
    guard let parameters else { return name }
    if let summary = decodePossiblyQuotedString(parameters["toolSummary"]), !summary.isEmpty {
        if let command = decodePossiblyQuotedString(parameters["CommandLine"])
            ?? decodePossiblyQuotedString(parameters["command"])
        {
            return "\(summary) · $ \(cleanShellCommandTitle(command))"
        }
        return "\(name): \(summary)"
    }
    if let command = decodePossiblyQuotedString(parameters["CommandLine"])
        ?? decodePossiblyQuotedString(parameters["command"])
    {
        return "$ \(cleanShellCommandTitle(command))"
    }
    if let path = decodePossiblyQuotedString(parameters["Path"])
        ?? decodePossiblyQuotedString(parameters["AbsolutePath"])
        ?? decodePossiblyQuotedString(parameters["SearchPath"])
    {
        return "\(name): \(shortenPath(path))"
    }
    if let query = decodePossiblyQuotedString(parameters["Query"])
        ?? decodePossiblyQuotedString(parameters["query"])
    {
        return "\(name): \(query)"
    }
    return name
}

private func extractUserRequestBody(_ raw: String) -> String {
    if let start = raw.range(of: "<USER_REQUEST>"),
        let end = raw.range(of: "</USER_REQUEST>", range: start.upperBound..<raw.endIndex)
    {
        return raw[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func extractPRNumber(from prompt: String) -> Int? {
    for marker in ["PR #", "on PR #", "pull/"] {
        if let range = prompt.range(of: marker) {
            let suffix = prompt[range.upperBound...]
            let digits = suffix.prefix(while: { $0.isNumber })
            if let num = Int(digits) {
                return num
            }
        }
    }
    return nil
}

private func classifyPromptPhase(_ prompt: String) -> (kind: String, phase: String)? {
    if prompt.hasPrefix("Review PR #") {
        return ("review-loop", "review")
    }
    if prompt.hasPrefix("Address review comments on PR #") {
        return ("review-loop", "address")
    }
    if prompt.hasPrefix("You were asked by ") {
        return ("ask", "ask")
    }
    return nil
}

private func defaultPhaseLabel(_ phase: String) -> String {
    if phase.hasPrefix("review-") {
        return "Review"
    }
    switch phase {
    case "review": return "Review"
    case "address": return "Address"
    case "ask": return "Ask"
    default: return phase.capitalized
    }
}

private func phaseSortRank(_ phase: String) -> (Int, Int, String) {
    if phase.hasPrefix("review-") {
        let model = String(phase.dropFirst("review-".count))
        let order = ["sol": 0, "neon": 1, "hydrogen": 2, "opus": 3]
        return (0, order[model] ?? 99, phase)
    }
    if phase == "address" {
        return (1, 0, phase)
    }
    if phase == "ask" {
        return (2, 0, phase)
    }
    return (3, 0, phase)
}

// MARK: - Stream Parsers

private struct StreamAccumulator {
    var sessionID: String?
    var model: String?
    var prompt: String?
    var events: [MonitorEvent] = []
    var indexByID: [String: Int] = [:]
    var usage = TokenUsageSummary()
    var hasAuthoritativeUsage = false
    var resultStatus: String?
    var resultError: String?
    var rawLineCounter = 0

    mutating func upsert(_ event: MonitorEvent) {
        if let existingIndex = indexByID[event.id] {
            var current = events[existingIndex]
            current.status = event.status
            if let title = event.title, !title.isEmpty { current.title = title }
            if let text = event.text { current.text = text }
            if let output = event.output, !output.isEmpty { current.output = output }
            if let exitCode = event.exitCode { current.exitCode = exitCode }
            if let duration = event.durationSeconds { current.durationSeconds = duration }
            if let timestamp = event.timestamp { current.timestamp = timestamp }
            events[existingIndex] = current
        } else {
            indexByID[event.id] = events.count
            events.append(event)
        }
    }

    mutating func appendDelta(
        id: String,
        kind: String,
        status: String,
        delta: String?,
        title: String? = nil,
        durationSeconds: Double? = nil,
        timestamp: String? = nil
    ) {
        if let existingIndex = indexByID[id] {
            var current = events[existingIndex]
            current.status = status
            if let delta {
                current.text = (current.text ?? "") + delta
            }
            if let title, !title.isEmpty { current.title = title }
            if let durationSeconds { current.durationSeconds = durationSeconds }
            if let timestamp { current.timestamp = timestamp }
            events[existingIndex] = current
        } else {
            indexByID[id] = events.count
            events.append(
                MonitorEvent(
                    id: id,
                    kind: kind,
                    status: status,
                    title: title,
                    text: delta,
                    output: nil,
                    exitCode: nil,
                    durationSeconds: durationSeconds,
                    timestamp: timestamp
                ))
        }
    }

    mutating func appendRawLine(_ line: String) {
        let trimmed = stripANSI(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.hasPrefix("##[group]") || trimmed.hasPrefix("##[endgroup]") {
            return
        }
        let lower = trimmed.lowercased()
        let isError =
            lower.hasPrefix("error:")
            || lower.hasPrefix("##[error]")
            || lower.contains("authentication failed")
            || lower.contains("authentication required")
        let kind = isError ? "error" : "notice"

        if let lastIndex = events.indices.last,
            events[lastIndex].kind == kind,
            events[lastIndex].id.hasPrefix("raw-")
        {
            events[lastIndex].text = [events[lastIndex].text, trimmed]
                .compactMap { $0 }
                .joined(separator: "\n")
            return
        }

        rawLineCounter += 1
        let id = "raw-\(rawLineCounter)"
        upsert(
            MonitorEvent(
                id: id,
                kind: kind,
                status: isError ? "failed" : "completed",
                title: isError ? "Error" : "Output",
                text: trimmed,
                output: nil,
                exitCode: nil,
                durationSeconds: nil,
                timestamp: nil
            ))
    }
}

/// Parses live NDJSON output from `codex exec --json`, `agy --output-format stream-json`,
/// Codex `rollout-*.jsonl` files, and `agy` CLI `transcript.jsonl` files.
func parseAgentStream(text: String) -> ParsedPhaseStream {
    var acc = StreamAccumulator()
    var pendingAgyToolIDs: [String] = []

    for rawLine in text.split(whereSeparator: \.isNewline) {
        let line = String(rawLine)
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }

        guard trimmed.hasPrefix("{"), let obj = parseJSONObject(trimmed) else {
            acc.appendRawLine(line)
            continue
        }

        if let eventType = stringValue(obj["event"]) {
            handleAgyStreamEvent(eventType: eventType, obj: obj, acc: &acc)
        } else if obj["step_index"] != nil, let transcriptType = stringValue(obj["type"]) {
            handleAgyTranscriptStep(
                type: transcriptType,
                obj: obj,
                acc: &acc,
                pendingToolIDs: &pendingAgyToolIDs
            )
        } else if let codexType = stringValue(obj["type"]) {
            handleCodexEvent(type: codexType, obj: obj, acc: &acc)
        } else {
            acc.appendRawLine(line)
        }
    }

    return ParsedPhaseStream(
        sessionID: acc.sessionID,
        model: acc.model,
        prompt: acc.prompt,
        events: acc.events,
        usage: acc.usage,
        resultStatus: acc.resultStatus,
        resultError: acc.resultError
    )
}

private func handleAgyTranscriptStep(
    type: String,
    obj: [String: Any],
    acc: inout StreamAccumulator,
    pendingToolIDs: inout [String]
) {
    let stepIndex = intValue(obj["step_index"]) ?? acc.events.count
    let timestamp = stringValue(obj["created_at"])
    let statusRaw = stringValue(obj["status"]) ?? "DONE"

    switch type {
    case "USER_INPUT":
        if acc.prompt == nil, let content = stringValue(obj["content"]) {
            acc.prompt = extractUserRequestBody(content)
        }

    case "PLANNER_RESPONSE":
        pendingToolIDs.removeAll()
        if let model = stringValue(obj["model"]), !model.isEmpty {
            acc.model = model
        }
        acc.usage.inputTokens += intValue(obj["input_tokens"]) ?? 0
        acc.usage.cachedInputTokens += intValue(obj["cache_read_tokens"]) ?? 0
        acc.usage.outputTokens += intValue(obj["output_tokens"]) ?? 0

        if let thinking = stringValue(obj["thinking"])?.trimmingCharacters(
            in: .whitespacesAndNewlines),
            !thinking.isEmpty
        {
            acc.upsert(
                MonitorEvent(
                    id: "tr-think-\(stepIndex)",
                    kind: "reasoning",
                    status: statusRaw == "DONE" ? "completed" : "running",
                    title: "Thinking",
                    text: thinking,
                    output: nil,
                    exitCode: nil,
                    durationSeconds: nil,
                    timestamp: timestamp
                ))
        }

        if let content = stringValue(obj["content"])?.trimmingCharacters(
            in: .whitespacesAndNewlines),
            !content.isEmpty
        {
            acc.upsert(
                MonitorEvent(
                    id: "tr-msg-\(stepIndex)",
                    kind: "message",
                    status: statusRaw == "DONE" ? "completed" : "running",
                    title: nil,
                    text: content,
                    output: nil,
                    exitCode: nil,
                    durationSeconds: nil,
                    timestamp: timestamp
                ))
        }

        let toolCalls = (obj["tool_calls"] as? [[String: Any]]) ?? []
        for (callIndex, call) in toolCalls.enumerated() {
            let toolName = stringValue(call["name"]) ?? "tool"
            let args = call["args"] as? [String: Any]
            let eventID = "tr-tool-\(stepIndex)-\(callIndex)"
            pendingToolIDs.append(eventID)
            let isCommand = toolName == "run_command"
            let title = formatToolSummary(name: toolName, parameters: args)
            let bodyText =
                isCommand
                ? decodePossiblyQuotedString(args?["CommandLine"])
                : prettyJSONString(args)
            acc.upsert(
                MonitorEvent(
                    id: eventID,
                    kind: isCommand ? "command" : "tool",
                    status: "running",
                    title: title,
                    text: bodyText,
                    output: nil,
                    exitCode: nil,
                    durationSeconds: nil,
                    timestamp: timestamp
                ))
        }

    case "GENERIC":
        let output = stringValue(obj["content"]) ?? ""
        if !pendingToolIDs.isEmpty {
            let toolID = pendingToolIDs.removeFirst()
            if let existingIndex = acc.indexByID[toolID] {
                var event = acc.events[existingIndex]
                event.output = output
                let failed =
                    statusRaw == "ERROR"
                    || output.contains("Command exited with code ")
                        && !output.contains("Command exited with code 0.")
                event.status = failed ? "failed" : "completed"
                if let range = output.range(of: "Command exited with code ") {
                    let digits = output[range.upperBound...].prefix(while: { $0.isNumber })
                    event.exitCode = Int(digits)
                }
                acc.events[existingIndex] = event
            }
        }

    case "ERROR_MESSAGE":
        let errText =
            stringValue(obj["error"])
            ?? stringValue(obj["content"])
            ?? "Agent error"
        acc.upsert(
            MonitorEvent(
                id: "tr-err-\(stepIndex)",
                kind: "error",
                status: "failed",
                title: "Error",
                text: errText,
                output: nil,
                exitCode: nil,
                durationSeconds: nil,
                timestamp: timestamp
            ))

    case "SYSTEM_MESSAGE":
        let text = stringValue(obj["content"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.contains("finished with result:") || text.contains("Stop hook") {
            let compact = text.components(separatedBy: .newlines).prefix(6).joined(separator: "\n")
            acc.upsert(
                MonitorEvent(
                    id: "tr-sys-\(stepIndex)",
                    kind: "notice",
                    status: "completed",
                    title: "System",
                    text: compact,
                    output: nil,
                    exitCode: nil,
                    durationSeconds: nil,
                    timestamp: timestamp
                ))
        }

    default:
        break
    }
}

private func handleAgyStreamEvent(
    eventType: String,
    obj: [String: Any],
    acc: inout StreamAccumulator
) {
    switch eventType {
    case "init":
        if let convID = stringValue(obj["conversation_id"]), !convID.isEmpty {
            acc.sessionID = convID
        }
        if let initObj = obj["init"] as? [String: Any],
            let model = stringValue(initObj["model"]), !model.isEmpty
        {
            acc.model = model
        }

    case "step_update":
        guard let step = obj["step_update"] as? [String: Any] else { return }
        if acc.sessionID == nil, let convID = stringValue(step["conversation_id"]), !convID.isEmpty
        {
            acc.sessionID = convID
        }
        let stepIndex = intValue(step["step_index"]) ?? 0
        let state = stringValue(step["state"]) ?? "ACTIVE"
        let stepType = stringValue(step["step_type"]) ?? ""
        let duration = doubleValue(step["duration_seconds"])
        let normalizedStatus = state == "DONE" ? "completed" : "running"

        switch stepType {
        case "user_input":
            return

        case "agent_response":
            if let thinkingDelta = stringValue(step["thinking_delta"]), !thinkingDelta.isEmpty {
                acc.appendDelta(
                    id: "agy-think-\(stepIndex)",
                    kind: "reasoning",
                    status: normalizedStatus,
                    delta: thinkingDelta,
                    title: "Thinking",
                    durationSeconds: duration
                )
            }
            let textDelta = stringValue(step["text_delta"])
            if let textDelta, !textDelta.isEmpty {
                acc.appendDelta(
                    id: "agy-msg-\(stepIndex)",
                    kind: "message",
                    status: normalizedStatus,
                    delta: textDelta,
                    durationSeconds: duration
                )
            } else if state == "DONE", let existingIdx = acc.indexByID["agy-msg-\(stepIndex)"] {
                acc.events[existingIdx].status = "completed"
                if let duration { acc.events[existingIdx].durationSeconds = duration }
            }

            if let usage = step["usage"] as? [String: Any], state == "DONE" {
                let thinking = intValue(usage["thinking_tokens"]) ?? 0
                if !acc.hasAuthoritativeUsage {
                    acc.usage.inputTokens += intValue(usage["input_tokens"]) ?? 0
                    acc.usage.cachedInputTokens += intValue(usage["cache_read_tokens"]) ?? 0
                    acc.usage.outputTokens += intValue(usage["output_tokens"]) ?? 0
                    acc.usage.thinkingTokens += thinking
                }
                if acc.indexByID["agy-msg-\(stepIndex)"] == nil
                    && acc.indexByID["agy-think-\(stepIndex)"] == nil
                    && thinking > 0
                {
                    let durationLabel = duration.map { String(format: "%.1fs", $0) } ?? ""
                    let detail =
                        durationLabel.isEmpty
                        ? "Thought (\(thinking) tokens)"
                        : "Thought for \(durationLabel) (\(thinking) tokens)"
                    acc.upsert(
                        MonitorEvent(
                            id: "agy-think-\(stepIndex)",
                            kind: "reasoning",
                            status: "completed",
                            title: "Thinking",
                            text: detail,
                            output: nil,
                            exitCode: nil,
                            durationSeconds: duration,
                            timestamp: nil
                        ))
                }
            }

        case "tool":
            let toolName = stringValue(step["tool_name"]) ?? "tool"
            let toolInfo = step["tool_info"] as? [String: Any]
            let params = toolInfo?["parameters"] as? [String: Any]
            let output = stringValue(toolInfo?["output"])
            let summary = formatToolSummary(name: toolName, parameters: params)
            let paramText =
                toolName == "run_command"
                ? decodePossiblyQuotedString(params?["CommandLine"])
                : prettyJSONString(params)
            acc.upsert(
                MonitorEvent(
                    id: "agy-tool-\(stepIndex)",
                    kind: toolName == "run_command" ? "command" : "tool",
                    status: normalizedStatus,
                    title: summary,
                    text: paramText,
                    output: output,
                    exitCode: nil,
                    durationSeconds: duration,
                    timestamp: nil
                ))

        default:
            break
        }

    case "result":
        guard let result = obj["result"] as? [String: Any] else { return }
        if acc.sessionID == nil,
            let convID = stringValue(result["conversation_id"]),
            !convID.isEmpty
        {
            acc.sessionID = convID
        }
        acc.resultStatus = stringValue(result["status"])
        let errorText = stringValue(result["error"])
        if let errorText, !errorText.isEmpty {
            acc.resultError = errorText
            let alreadyCaptured = acc.events.contains {
                $0.kind == "error" && ($0.text?.contains(errorText) ?? false)
            }
            if !alreadyCaptured {
                acc.upsert(
                    MonitorEvent(
                        id: "agy-result-error",
                        kind: "error",
                        status: "failed",
                        title: "Error",
                        text: errorText,
                        output: nil,
                        exitCode: nil,
                        durationSeconds: doubleValue(result["duration_seconds"]),
                        timestamp: nil
                    ))
            }
        }
        if let usage = result["usage"] as? [String: Any] {
            acc.hasAuthoritativeUsage = true
            acc.usage = TokenUsageSummary(
                inputTokens: intValue(usage["input_tokens"]) ?? 0,
                cachedInputTokens: intValue(usage["cache_read_tokens"]) ?? 0,
                outputTokens: intValue(usage["output_tokens"]) ?? 0,
                thinkingTokens: intValue(usage["thinking_tokens"]) ?? 0
            )
        }

    default:
        break
    }
}

private func handleCodexEvent(
    type: String,
    obj: [String: Any],
    acc: inout StreamAccumulator
) {
    let timestamp = stringValue(obj["timestamp"])

    switch type {
    case "thread.started":
        if let threadID = stringValue(obj["thread_id"]), !threadID.isEmpty {
            acc.sessionID = threadID
        }

    case "item.started", "item.updated", "item.completed":
        guard let item = obj["item"] as? [String: Any],
            let itemID = stringValue(item["id"]),
            let itemType = stringValue(item["type"])
        else { return }
        let rawStatus = stringValue(item["status"]) ?? ""
        let status: String
        if type == "item.started" || rawStatus == "in_progress" {
            status = "running"
        } else if rawStatus == "failed" {
            status = "failed"
        } else {
            status = "completed"
        }

        switch itemType {
        case "agent_message":
            acc.upsert(
                MonitorEvent(
                    id: itemID,
                    kind: "message",
                    status: status,
                    title: nil,
                    text: stringValue(item["text"]),
                    output: nil,
                    exitCode: nil,
                    durationSeconds: nil,
                    timestamp: timestamp
                ))

        case "reasoning":
            acc.upsert(
                MonitorEvent(
                    id: itemID,
                    kind: "reasoning",
                    status: status,
                    title: "Reasoning",
                    text: stringValue(item["text"]),
                    output: nil,
                    exitCode: nil,
                    durationSeconds: nil,
                    timestamp: timestamp
                ))

        case "command_execution":
            let command = stringValue(item["command"]) ?? "command"
            let output = stringValue(item["aggregated_output"])
            let exitCode = intValue(item["exit_code"])
            let resolvedStatus =
                status == "running" ? "running" : ((exitCode ?? 0) == 0 ? "completed" : "failed")
            acc.upsert(
                MonitorEvent(
                    id: itemID,
                    kind: "command",
                    status: resolvedStatus,
                    title: "$ \(cleanShellCommandTitle(command))",
                    text: command,
                    output: output,
                    exitCode: exitCode,
                    durationSeconds: nil,
                    timestamp: timestamp
                ))

        case "mcp_tool_call":
            let server = stringValue(item["server"]) ?? "mcp"
            let tool = stringValue(item["tool"]) ?? "call"
            let argsText = prettyJSONString(item["arguments"])
            let resultText = prettyJSONString(item["result"]) ?? prettyJSONString(item["error"])
            let hasError = item["error"] != nil && !(item["error"] is NSNull)
            acc.upsert(
                MonitorEvent(
                    id: itemID,
                    kind: "tool",
                    status: hasError ? "failed" : status,
                    title: "\(server).\(tool)",
                    text: argsText,
                    output: resultText,
                    exitCode: nil,
                    durationSeconds: nil,
                    timestamp: timestamp
                ))

        case "file_change":
            let changes = (item["changes"] as? [[String: Any]]) ?? []
            let lines = changes.compactMap { change -> String? in
                guard let path = stringValue(change["path"]) else { return nil }
                let kind = stringValue(change["kind"]) ?? "update"
                return "\(kind): \(path)"
            }
            acc.upsert(
                MonitorEvent(
                    id: itemID,
                    kind: "file_change",
                    status: status,
                    title: "File Changes (\(lines.count))",
                    text: lines.joined(separator: "\n"),
                    output: nil,
                    exitCode: nil,
                    durationSeconds: nil,
                    timestamp: timestamp
                ))

        case "web_search":
            let query = stringValue(item["query"]) ?? ""
            acc.upsert(
                MonitorEvent(
                    id: itemID,
                    kind: "tool",
                    status: status,
                    title: "web_search: \(query)",
                    text: nil,
                    output: nil,
                    exitCode: nil,
                    durationSeconds: nil,
                    timestamp: timestamp
                ))

        case "error":
            let message = stringValue(item["message"]) ?? ""
            let isHookNotice = message.contains("--dangerously-bypass-hook-trust")
            acc.upsert(
                MonitorEvent(
                    id: itemID,
                    kind: isHookNotice ? "notice" : "error",
                    status: isHookNotice ? "completed" : "failed",
                    title: isHookNotice ? "Notice" : "Error",
                    text: message,
                    output: nil,
                    exitCode: nil,
                    durationSeconds: nil,
                    timestamp: timestamp
                ))

        default:
            break
        }

    case "turn.completed":
        if let usage = obj["usage"] as? [String: Any] {
            acc.usage.inputTokens += intValue(usage["input_tokens"]) ?? 0
            acc.usage.cachedInputTokens += intValue(usage["cached_input_tokens"]) ?? 0
            acc.usage.outputTokens += intValue(usage["output_tokens"]) ?? 0
        }

    case "turn.failed", "error":
        let message =
            stringValue((obj["error"] as? [String: Any])?["message"])
            ?? stringValue(obj["message"])
            ?? "Turn failed"
        acc.resultStatus = "ERROR"
        acc.resultError = message
        acc.upsert(
            MonitorEvent(
                id: "codex-turn-error-\(acc.events.count)",
                kind: "error",
                status: "failed",
                title: "Error",
                text: message,
                output: nil,
                exitCode: nil,
                durationSeconds: nil,
                timestamp: timestamp
            ))

    // Codex rollout file fallback support (`~/.codex/sessions/.../rollout-*.jsonl`)
    case "session_meta":
        if let payload = obj["payload"] as? [String: Any],
            let sessionID = stringValue(payload["id"]) ?? stringValue(payload["session_id"])
        {
            acc.sessionID = sessionID
        }

    case "event_msg":
        guard let payload = obj["payload"] as? [String: Any],
            let payloadType = stringValue(payload["type"])
        else { return }

        switch payloadType {
        case "thread_settings_applied":
            if let settings = payload["thread_settings"] as? [String: Any],
                let model = stringValue(settings["model"])
            {
                acc.model = model
            }

        case "item_completed":
            guard let item = payload["item"] as? [String: Any],
                let itemID = stringValue(item["id"]),
                let itemType = stringValue(item["type"])
            else { return }

            switch itemType {
            case "UserMessage":
                let parts = (item["content"] as? [[String: Any]]) ?? []
                let text = parts.compactMap { stringValue($0["text"]) }.joined(separator: "\n")
                if !text.isEmpty { acc.prompt = text }

            case "AgentMessage":
                let parts = (item["content"] as? [[String: Any]]) ?? []
                let text = parts.compactMap { stringValue($0["text"]) }.joined(separator: "\n")
                acc.upsert(
                    MonitorEvent(
                        id: itemID,
                        kind: "message",
                        status: "completed",
                        title: nil,
                        text: text,
                        output: nil,
                        exitCode: nil,
                        durationSeconds: nil,
                        timestamp: timestamp
                    ))

            case "CommandExecution":
                let commandParts = (item["command"] as? [String]) ?? []
                let rawCommand: String
                if commandParts.count == 3, commandParts[1] == "-lc" {
                    rawCommand = commandParts[2]
                } else if !commandParts.isEmpty {
                    rawCommand = commandParts.joined(separator: " ")
                } else {
                    rawCommand = stringValue(item["command"]) ?? "command"
                }
                let output = stringValue(item["aggregated_output"])
                let exitCode = intValue(item["exit_code"])
                let duration: Double?
                if let durObj = item["duration"] as? [String: Any],
                    let secs = doubleValue(durObj["secs"])
                {
                    let nanos = doubleValue(durObj["nanos"]) ?? 0
                    duration = secs + nanos / 1_000_000_000.0
                } else {
                    duration = doubleValue(item["duration_ms"]).map { $0 / 1000.0 }
                }
                acc.upsert(
                    MonitorEvent(
                        id: itemID,
                        kind: "command",
                        status: (exitCode ?? 0) == 0 ? "completed" : "failed",
                        title: "$ \(cleanShellCommandTitle(rawCommand))",
                        text: rawCommand,
                        output: output,
                        exitCode: exitCode,
                        durationSeconds: duration,
                        timestamp: timestamp
                    ))

            case "Reasoning":
                let summaryParts = (item["summary_text"] as? [String]) ?? []
                let summaryText = summaryParts.joined(separator: "\n")
                if !summaryText.isEmpty {
                    acc.upsert(
                        MonitorEvent(
                            id: itemID,
                            kind: "reasoning",
                            status: "completed",
                            title: "Reasoning",
                            text: summaryText,
                            output: nil,
                            exitCode: nil,
                            durationSeconds: nil,
                            timestamp: timestamp
                        ))
                }

            default:
                break
            }

        case "token_count":
            if let info = payload["info"] as? [String: Any],
                let total = info["total_token_usage"] as? [String: Any]
            {
                acc.hasAuthoritativeUsage = true
                acc.usage = TokenUsageSummary(
                    inputTokens: intValue(total["input_tokens"]) ?? 0,
                    cachedInputTokens: intValue(total["cached_input_tokens"]) ?? 0,
                    outputTokens: intValue(total["output_tokens"]) ?? 0,
                    thinkingTokens: intValue(total["reasoning_output_tokens"]) ?? 0
                )
            }

        case "task_complete":
            acc.resultStatus = "SUCCESS"

        default:
            break
        }

    default:
        break
    }
}

// MARK: - Discovery

private struct LocalPhaseEntry {
    let prNumber: Int?
    let kind: String
    let basePhase: String
    let sessionID: String
    let startedAt: String
    let updatedAt: String
    let isLive: Bool
    let phaseView: MonitorPhaseView
}

private func parseRolloutHeader(firstLines: [String]) -> (
    sessionID: String, cwd: String, model: String?, prompt: String, startedAt: String
)? {
    var sessionID: String?
    var cwd: String?
    var startedAt: String?
    var model: String?
    var prompt: String?

    for line in firstLines {
        guard let obj = parseJSONObject(line),
            let type = stringValue(obj["type"])
        else { continue }
        if type == "session_meta", let payload = obj["payload"] as? [String: Any] {
            sessionID = stringValue(payload["id"]) ?? stringValue(payload["session_id"])
            cwd = stringValue(payload["cwd"])
            startedAt = stringValue(payload["timestamp"]) ?? stringValue(obj["timestamp"])
        } else if type == "event_msg", let payload = obj["payload"] as? [String: Any] {
            let pType = stringValue(payload["type"])
            if pType == "thread_settings_applied",
                let settings = payload["thread_settings"] as? [String: Any]
            {
                model = stringValue(settings["model"])
            } else if pType == "item_completed",
                let item = payload["item"] as? [String: Any],
                stringValue(item["type"]) == "UserMessage"
            {
                let parts = (item["content"] as? [[String: Any]]) ?? []
                prompt = parts.compactMap { stringValue($0["text"]) }.joined(separator: "\n")
            }
        }
    }

    guard let sessionID, let cwd, let prompt, let startedAt else { return nil }
    return (sessionID, cwd, model, prompt, startedAt)
}

private func discoverLocalCodexPhases(
    codexSessionsDir: String,
    knownSessionIDs: Set<String>,
    now: Date
) -> [LocalPhaseEntry] {
    let fm = FileManager.default
    let rootURL = URL(fileURLWithPath: codexSessionsDir, isDirectory: true)
    guard fm.fileExists(atPath: rootURL.path) else { return [] }

    guard let enumerator = fm.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
    var candidateFiles: [(url: URL, modified: Date)] = []

    while let url = enumerator.nextObject() as? URL {
        guard url.pathExtension == "jsonl" else { continue }
        guard let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .isRegularFileKey]),
            values.isRegularFile == true,
            let modified = values.contentModificationDate,
            modified >= cutoff
        else { continue }
        candidateFiles.append((url, modified))
    }

    candidateFiles.sort { $0.modified > $1.modified }
    let isoFormatter = ISO8601DateFormatter()
    var entries: [LocalPhaseEntry] = []

    for candidate in candidateFiles.prefix(30) {
        guard let content = try? String(contentsOf: candidate.url, encoding: .utf8) else {
            continue
        }
        let lines = content.split(whereSeparator: \.isNewline).map(String.init)
        guard let meta = parseRolloutHeader(firstLines: Array(lines.prefix(25))),
            !knownSessionIDs.contains(meta.sessionID)
        else { continue }

        let classified = classifyPromptPhase(meta.prompt)
        guard classified != nil || meta.cwd.contains("/clinical-agents/work/") else { continue }
        let (kind, phase) = classified ?? ("review-loop", "review")

        let parsed = parseAgentStream(text: content)
        let isCompleted = parsed.resultStatus != nil || now.timeIntervalSince(candidate.modified) > 90
        let updatedISO = isoFormatter.string(from: candidate.modified)
        let prNumber = extractPRNumber(from: meta.prompt)

        let phaseView = MonitorPhaseView(
            phase: phase,
            label: defaultPhaseLabel(phase),
            harness: "codex",
            botLogin: "clinical-codex[bot]",
            model: meta.model ?? parsed.model,
            effort: nil,
            worktreePath: meta.cwd,
            prompt: meta.prompt,
            status: isCompleted ? "completed" : "running",
            conclusion: isCompleted ? (parsed.resultError == nil ? "success" : "failure") : nil,
            startedAt: meta.startedAt,
            completedAt: isCompleted ? updatedISO : nil,
            updatedAt: updatedISO,
            sessionID: meta.sessionID,
            usage: parsed.usage,
            resultStatus: parsed.resultStatus,
            resultError: parsed.resultError,
            events: parsed.events
        )

        entries.append(
            LocalPhaseEntry(
                prNumber: prNumber,
                kind: kind,
                basePhase: phase,
                sessionID: meta.sessionID,
                startedAt: meta.startedAt,
                updatedAt: updatedISO,
                isLive: !isCompleted,
                phaseView: phaseView
            ))
    }

    return entries
}

private func discoverLocalAgyPhases(
    agyBrainDir: String,
    knownSessionIDs: Set<String>,
    now: Date
) -> [LocalPhaseEntry] {
    let fm = FileManager.default
    let rootURL = URL(fileURLWithPath: agyBrainDir, isDirectory: true)
    guard fm.fileExists(atPath: rootURL.path) else { return [] }
    guard let convDirs = try? fm.contentsOfDirectory(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
    var candidates: [(id: String, url: URL, modified: Date)] = []

    for convDir in convDirs {
        let convID = convDir.lastPathComponent
        guard !knownSessionIDs.contains(convID) else { continue }
        let transcriptURL = convDir
            .appending(path: ".system_generated", directoryHint: .isDirectory)
            .appending(path: "logs", directoryHint: .isDirectory)
            .appending(path: "transcript.jsonl")
        guard let values = try? transcriptURL.resourceValues(
            forKeys: [.contentModificationDateKey, .isRegularFileKey]),
            values.isRegularFile == true,
            let modified = values.contentModificationDate,
            modified >= cutoff
        else { continue }
        candidates.append((convID, transcriptURL, modified))
    }

    candidates.sort { $0.modified > $1.modified }
    let isoFormatter = ISO8601DateFormatter()
    var entries: [LocalPhaseEntry] = []

    for candidate in candidates.prefix(40) {
        guard let content = try? String(contentsOf: candidate.url, encoding: .utf8) else {
            continue
        }
        let lines = content.split(whereSeparator: \.isNewline).map(String.init)
        guard let firstLine = lines.first,
            let firstObj = parseJSONObject(firstLine),
            stringValue(firstObj["type"]) == "USER_INPUT",
            let rawContent = stringValue(firstObj["content"])
        else { continue }

        let prompt = extractUserRequestBody(rawContent)
        guard let (kind, phase) = classifyPromptPhase(prompt) else { continue }

        let parsed = parseAgentStream(text: content)
        let startedAt =
            stringValue(firstObj["created_at"]) ?? isoFormatter.string(from: candidate.modified)
        let updatedISO = isoFormatter.string(from: candidate.modified)

        // An agy CLI transcript is still live if updated recently and has not ended on a final assistant reply.
        let lastObj = lines.last.flatMap(parseJSONObject)
        let lastType = stringValue(lastObj?["type"]) ?? ""
        let lastHasTools = !((lastObj?["tool_calls"] as? [[String: Any]]) ?? []).isEmpty
        let lastHasContent =
            !(stringValue(lastObj?["content"])?.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ?? true)
        let endedCleanly =
            lastType == "PLANNER_RESPONSE" && !lastHasTools && lastHasContent
            && stringValue(lastObj?["status"]) == "DONE"
        let isLive = !endedCleanly && now.timeIntervalSince(candidate.modified) < 120
        let hasTrailingError = lastType == "ERROR_MESSAGE" && !isLive

        let phaseView = MonitorPhaseView(
            phase: phase,
            label: defaultPhaseLabel(phase),
            harness: "antigravity",
            botLogin: "clinical-antigravity[bot]",
            model: parsed.model,
            effort: nil,
            worktreePath: nil,
            prompt: prompt,
            status: isLive ? "running" : "completed",
            conclusion: isLive ? nil : (hasTrailingError ? "failure" : "success"),
            startedAt: startedAt,
            completedAt: isLive ? nil : updatedISO,
            updatedAt: updatedISO,
            sessionID: candidate.id,
            usage: parsed.usage,
            resultStatus: endedCleanly ? "SUCCESS" : nil,
            resultError: hasTrailingError ? parsed.events.last(where: { $0.kind == "error" })?.text : nil,
            events: parsed.events
        )

        entries.append(
            LocalPhaseEntry(
                prNumber: extractPRNumber(from: prompt),
                kind: kind,
                basePhase: phase,
                sessionID: candidate.id,
                startedAt: startedAt,
                updatedAt: updatedISO,
                isLive: isLive,
                phaseView: phaseView
            ))
    }

    return entries
}

/// Groups local Codex and Antigravity sessions for the same PR into tabbed loop runs.
private func groupLocalPhasesIntoRuns(_ entries: [LocalPhaseEntry]) -> [MonitorRunView] {
    var byPR: [Int: [LocalPhaseEntry]] = [:]
    var ungrouped: [LocalPhaseEntry] = []

    for entry in entries {
        if let pr = entry.prNumber {
            byPR[pr, default: []].append(entry)
        } else {
            ungrouped.append(entry)
        }
    }

    var runs: [MonitorRunView] = []

    for (prNumber, group) in byPR {
        let sorted = group.sorted { $0.startedAt < $1.startedAt }
        var phaseCounts: [String: Int] = [:]
        var phases: [MonitorPhaseView] = []

        for entry in sorted {
            let count = (phaseCounts[entry.basePhase] ?? 0) + 1
            phaseCounts[entry.basePhase] = count
            let key = count == 1 ? entry.basePhase : "\(entry.basePhase)-\(count)"
            let label =
                count == 1
                ? defaultPhaseLabel(entry.basePhase)
                : "\(defaultPhaseLabel(entry.basePhase)) #\(count)"
            let p = entry.phaseView
            phases.append(
                MonitorPhaseView(
                    phase: key,
                    label: label,
                    harness: p.harness,
                    botLogin: p.botLogin,
                    model: p.model,
                    effort: p.effort,
                    worktreePath: p.worktreePath,
                    prompt: p.prompt,
                    status: p.status,
                    conclusion: p.conclusion,
                    startedAt: p.startedAt,
                    completedAt: p.completedAt,
                    updatedAt: p.updatedAt,
                    sessionID: p.sessionID,
                    usage: p.usage,
                    resultStatus: p.resultStatus,
                    resultError: p.resultError,
                    events: p.events
                ))
        }

        let createdAt = sorted.first?.startedAt ?? ""
        let updatedAt = sorted.map(\.updatedAt).max() ?? createdAt
        let isLive = sorted.contains { $0.isLive }
        let kind = sorted.contains { $0.kind == "review-loop" } ? "review-loop" : "ask"

        runs.append(
            MonitorRunView(
                runID: "local-pr-\(prNumber)",
                kind: kind,
                source: "local-sessions",
                prNumber: prNumber,
                prBranch: nil,
                prHeadSHA: nil,
                repository: "vickychijwani/clinical-swift",
                runURL: nil,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isLive: isLive,
                phases: phases
            ))
    }

    for entry in ungrouped {
        runs.append(
            MonitorRunView(
                runID: "local-\(entry.sessionID)",
                kind: entry.kind,
                source: "local-sessions",
                prNumber: nil,
                prBranch: nil,
                prHeadSHA: nil,
                repository: "vickychijwani/clinical-swift",
                runURL: nil,
                createdAt: entry.startedAt,
                updatedAt: entry.updatedAt,
                isLive: entry.isLive,
                phases: [entry.phaseView]
            ))
    }

    return runs
}

/// Loads all recorded workflow runs plus local Codex and Antigravity CLI sessions.
func loadMonitorSnapshot(
    monitorDirectory: String,
    codexSessionsDirectory: String? = nil,
    agyBrainDirectory: String? = nil,
    now: Date = Date()
) -> MonitorSnapshot {
    let fm = FileManager.default
    let runsDir = URL(fileURLWithPath: monitorDirectory, isDirectory: true)
        .appending(path: "runs", directoryHint: .isDirectory)
    let isoFormatter = ISO8601DateFormatter()

    var runs: [MonitorRunView] = []
    var knownSessionIDs = Set<String>()

    if let entries = try? fm.contentsOfDirectory(
        at: runsDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) {
        for runDir in entries {
            let runFile = runDir.appending(path: "run.json")
            guard let runData = try? Data(contentsOf: runFile),
                let runRecord = try? JSONDecoder().decode(MonitorRunRecord.self, from: runData)
            else { continue }

            let phaseFiles =
                ((try? fm.contentsOfDirectory(
                    at: runDir,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )) ?? [])
                .filter { $0.pathExtension == "json" && $0.lastPathComponent != "run.json" }

            var decodedPhases: [MonitorPhaseRecord] = []
            for phaseFile in phaseFiles {
                guard let phaseData = try? Data(contentsOf: phaseFile),
                    let phaseRecord = try? JSONDecoder().decode(
                        MonitorPhaseRecord.self, from: phaseData),
                    phaseRecord.phase == "address" || phaseRecord.phase == "ask"
                        || phaseRecord.phase.hasPrefix("review-")
                else { continue }
                decodedPhases.append(phaseRecord)
            }
            decodedPhases.sort { phaseSortRank($0.phase) < phaseSortRank($1.phase) }

            var phases: [MonitorPhaseView] = []
            for phaseRecord in decodedPhases {

                let streamText: String
                if let streamPath = phaseRecord.streamFile,
                    let content = try? String(contentsOfFile: streamPath, encoding: .utf8)
                {
                    streamText = content
                } else {
                    streamText = ""
                }

                var parsed = parseAgentStream(text: streamText)
                if let sessionID = parsed.sessionID {
                    knownSessionIDs.insert(sessionID)
                    // Enrich agy stream-json runs with full thinking text from agy CLI's live transcript when available.
                    if phaseRecord.harness == "antigravity", let agyBrainDirectory {
                        let transcriptPath = URL(fileURLWithPath: agyBrainDirectory)
                            .appending(path: sessionID)
                            .appending(path: ".system_generated/logs/transcript.jsonl").path
                        if let transcriptContent = try? String(
                            contentsOfFile: transcriptPath, encoding: .utf8)
                        {
                            let enriched = parseAgentStream(text: transcriptContent)
                            if !enriched.events.isEmpty {
                                let streamErrors = parsed.events.filter { $0.kind == "error" }
                                var mergedEvents = enriched.events
                                for err in streamErrors {
                                    if !mergedEvents.contains(where: {
                                        $0.kind == "error" && $0.text == err.text
                                    }) {
                                        mergedEvents.append(err)
                                    }
                                }
                                parsed.events = mergedEvents
                                if !parsed.usage.totalTokens.description.isEmpty,
                                    parsed.usage.totalTokens == 0
                                {
                                    parsed.usage = enriched.usage
                                }
                            }
                        }
                    }
                }

                phases.append(
                    MonitorPhaseView(
                        phase: phaseRecord.phase,
                        label: defaultPhaseLabel(phaseRecord.phase),
                        harness: phaseRecord.harness,
                        botLogin: phaseRecord.botLogin,
                        model: phaseRecord.model ?? parsed.model,
                        effort: phaseRecord.effort,
                        worktreePath: phaseRecord.worktreePath,
                        prompt: phaseRecord.prompt ?? parsed.prompt,
                        status: phaseRecord.status,
                        conclusion: phaseRecord.conclusion,
                        startedAt: phaseRecord.startedAt,
                        completedAt: phaseRecord.completedAt,
                        updatedAt: phaseRecord.updatedAt,
                        sessionID: parsed.sessionID,
                        usage: parsed.usage,
                        resultStatus: parsed.resultStatus,
                        resultError: parsed.resultError,
                        events: parsed.events
                    ))
            }

            let isLive = phases.contains { $0.status == "running" || $0.status == "queued" }
            let latestPhaseUpdate = phases.map(\.updatedAt).max() ?? runRecord.updatedAt
            let updatedAt = max(runRecord.updatedAt, latestPhaseUpdate)

            runs.append(
                MonitorRunView(
                    runID: runRecord.runID,
                    kind: runRecord.kind
                        ?? (phases.contains { $0.phase == "ask" } ? "ask" : "review-loop"),
                    source: "workflow",
                    prNumber: runRecord.prNumber,
                    prBranch: runRecord.prBranch,
                    prHeadSHA: runRecord.prHeadSHA,
                    repository: runRecord.repository,
                    runURL: runRecord.runURL,
                    createdAt: runRecord.createdAt,
                    updatedAt: updatedAt,
                    isLive: isLive,
                    phases: phases
                ))
        }
    }

    var localPhases: [LocalPhaseEntry] = []
    if let codexSessionsDirectory {
        localPhases.append(
            contentsOf: discoverLocalCodexPhases(
                codexSessionsDir: codexSessionsDirectory,
                knownSessionIDs: knownSessionIDs,
                now: now
            ))
    }
    if let agyBrainDirectory {
        localPhases.append(
            contentsOf: discoverLocalAgyPhases(
                agyBrainDir: agyBrainDirectory,
                knownSessionIDs: knownSessionIDs,
                now: now
            ))
    }
    runs.append(contentsOf: groupLocalPhasesIntoRuns(localPhases))

    runs.sort { lhs, rhs in
        if lhs.isLive != rhs.isLive {
            return lhs.isLive && !rhs.isLive
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    return MonitorSnapshot(
        generatedAt: isoFormatter.string(from: now),
        runs: Array(runs.prefix(40))
    )
}

private func computeMonitorFingerprint(
    monitorDirectory: String,
    codexSessionsDirectory: String?,
    agyBrainDirectory: String?
) -> String {
    let fm = FileManager.default
    var parts: [String] = []
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]

    let runsURL = URL(fileURLWithPath: monitorDirectory, isDirectory: true)
        .appending(path: "runs", directoryHint: .isDirectory)
    if let enumerator = fm.enumerator(
        at: runsURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
    {
        while let url = enumerator.nextObject() as? URL {
            let ext = url.pathExtension
            guard ext == "json" || ext == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = values?.fileSize ?? 0
            let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            parts.append("r:\(url.path):\(size):\(Int(mtime * 1000))")
        }
    }

    if let codexSessionsDirectory {
        let codexURL = URL(fileURLWithPath: codexSessionsDirectory, isDirectory: true)
        if let enumerator = fm.enumerator(
            at: codexURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        {
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "jsonl" else { continue }
                let values = try? url.resourceValues(forKeys: Set(keys))
                let size = values?.fileSize ?? 0
                let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                parts.append("c:\(url.lastPathComponent):\(size):\(Int(mtime))")
            }
        }
    }

    if let agyBrainDirectory {
        let brainURL = URL(fileURLWithPath: agyBrainDirectory, isDirectory: true)
        if let convDirs = try? fm.contentsOfDirectory(
            at: brainURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        {
            for convDir in convDirs {
                let transcriptURL = convDir.appending(
                    path: ".system_generated/logs/transcript.jsonl")
                guard let values = try? transcriptURL.resourceValues(forKeys: Set(keys)) else {
                    continue
                }
                let size = values.fileSize ?? 0
                let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
                parts.append("a:\(convDir.lastPathComponent):\(size):\(Int(mtime * 1000))")
            }
        }
    }

    parts.sort()
    return parts.joined(separator: "|")
}

// MARK: - HTTP + SSE Server

private final class MonitorServer: @unchecked Sendable {
    private let port: UInt16
    private let monitorDirectory: String
    private let codexSessionsDirectory: String
    private let agyBrainDirectory: String
    private let queue = DispatchQueue(label: "in.bitehaus.clinical.agent-monitor")
    private var listener: NWListener?
    private var sseClients: [ObjectIdentifier: NWConnection] = [:]
    private var timer: DispatchSourceTimer?
    private var lastFingerprint = ""
    private var lastSnapshotData = Data()
    private var heartbeatCounter = 0

    init(
        port: UInt16,
        monitorDirectory: String,
        codexSessionsDirectory: String,
        agyBrainDirectory: String
    ) {
        self.port = port
        self.monitorDirectory = monitorDirectory
        self.codexSessionsDirectory = codexSessionsDirectory
        self.agyBrainDirectory = agyBrainDirectory
    }

    func start(openBrowser: Bool) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(
                domain: "AgentMonitor", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid port: \(port)"])
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: nwPort)
        self.listener = listener

        refreshSnapshotIfNeeded(force: true)

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let url = "http://127.0.0.1:\(self.port)"
                print("Clinical Agent Monitor listening on \(url)")
                print(
                    "Watching \(self.monitorDirectory)/runs, \(self.codexSessionsDirectory), and \(self.agyBrainDirectory)"
                )
                fflush(stdout)
                if openBrowser {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    process.arguments = [url]
                    try? process.run()
                }
            case .failed(let error):
                FileHandle.standardError.write(Data("Listener failed: \(error)\n".utf8))
                exit(1)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.start(queue: queue)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(350), repeating: .milliseconds(350))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        let changed = refreshSnapshotIfNeeded(force: false)
        if changed {
            broadcastSSE(event: "snapshot", data: lastSnapshotData)
            heartbeatCounter = 0
        } else {
            heartbeatCounter += 1
            if heartbeatCounter >= 40 {
                heartbeatCounter = 0
                broadcastPing()
            }
        }
    }

    @discardableResult
    private func refreshSnapshotIfNeeded(force: Bool) -> Bool {
        let fingerprint = computeMonitorFingerprint(
            monitorDirectory: monitorDirectory,
            codexSessionsDirectory: codexSessionsDirectory,
            agyBrainDirectory: agyBrainDirectory
        )
        guard force || fingerprint != lastFingerprint else { return false }
        lastFingerprint = fingerprint
        let snapshot = loadMonitorSnapshot(
            monitorDirectory: monitorDirectory,
            codexSessionsDirectory: codexSessionsDirectory,
            agyBrainDirectory: agyBrainDirectory
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            lastSnapshotData = data
        }
        return true
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                self.sseClients.removeValue(forKey: ObjectIdentifier(connection))
            default:
                break
            }
        }
        connection.start(queue: queue)
        readHTTPRequest(on: connection, buffer: Data())
    }

    private func readHTTPRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                _ = error
                connection.cancel()
                return
            }
            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }
            if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let headerText = String(decoding: accumulated[..<headerEnd.lowerBound], as: UTF8.self)
                self.routeRequest(headerText: headerText, connection: connection)
                return
            }
            if isComplete || accumulated.count > 65536 {
                connection.cancel()
                return
            }
            self.readHTTPRequest(on: connection, buffer: accumulated)
        }
    }

    private func routeRequest(headerText: String, connection: NWConnection) {
        let firstLine = headerText.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let parts = firstLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let rawPath = parts.count > 1 ? String(parts[1]) : "/"
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"

        guard method == "GET" || method == "HEAD" else {
            sendHTTPResponse(
                connection: connection,
                status: "405 Method Not Allowed",
                contentType: "text/plain; charset=utf-8",
                body: Data("Method Not Allowed\n".utf8)
            )
            return
        }

        let isHead = method == "HEAD"
        switch path {
        case "/", "/index.html":
            sendHTTPResponse(
                connection: connection,
                status: "200 OK",
                contentType: "text/html; charset=utf-8",
                body: Data(monitorHTML.utf8),
                headOnly: isHead
            )

        case "/api/snapshot":
            refreshSnapshotIfNeeded(force: false)
            sendHTTPResponse(
                connection: connection,
                status: "200 OK",
                contentType: "application/json; charset=utf-8",
                body: lastSnapshotData,
                headOnly: isHead
            )

        case "/api/events":
            startSSEStream(connection: connection)

        default:
            sendHTTPResponse(
                connection: connection,
                status: "404 Not Found",
                contentType: "text/plain; charset=utf-8",
                body: Data("Not Found\n".utf8),
                headOnly: isHead
            )
        }
    }

    private func sendHTTPResponse(
        connection: NWConnection,
        status: String,
        contentType: String,
        body: Data,
        headOnly: Bool = false
    ) {
        let header =
            "HTTP/1.1 \(status)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\n"
            + "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        if !headOnly {
            response.append(body)
        }
        connection.send(
            content: response,
            completion: .contentProcessed { _ in
                connection.cancel()
            })
    }

    private func startSSEStream(connection: NWConnection) {
        let header =
            "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/event-stream; charset=utf-8\r\n"
            + "Cache-Control: no-cache\r\n"
            + "Connection: keep-alive\r\n\r\n"
            + "retry: 1500\n\n"
        let id = ObjectIdentifier(connection)
        sseClients[id] = connection

        refreshSnapshotIfNeeded(force: false)
        var initialPayload = Data(header.utf8)
        initialPayload.append(formatSSE(event: "snapshot", data: lastSnapshotData))
        connection.send(
            content: initialPayload,
            completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.sseClients.removeValue(forKey: id)
                    connection.cancel()
                }
            })
    }

    private func formatSSE(event: String, data: Data) -> Data {
        var packet = Data("event: \(event)\ndata: ".utf8)
        packet.append(data)
        packet.append(Data("\n\n".utf8))
        return packet
    }

    private func broadcastSSE(event: String, data: Data) {
        let packet = formatSSE(event: event, data: data)
        for (id, connection) in sseClients {
            connection.send(
                content: packet,
                completion: .contentProcessed { [weak self] error in
                    if error != nil {
                        self?.sseClients.removeValue(forKey: id)
                        connection.cancel()
                    }
                })
        }
    }

    private func broadcastPing() {
        let packet = Data(": ping\n\n".utf8)
        for (id, connection) in sseClients {
            connection.send(
                content: packet,
                completion: .contentProcessed { [weak self] error in
                    if error != nil {
                        self?.sseClients.removeValue(forKey: id)
                        connection.cancel()
                    }
                })
        }
    }
}

// MARK: - Web UI

private let monitorHTML = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Clinical Agent Monitor</title>
<style>
  :root {
    color-scheme: light dark;
    --bg: #f6f7f9;
    --surface: #ffffff;
    --surface-2: #f1f3f6;
    --border: #e2e6ec;
    --text: #15181e;
    --muted: #5c6575;
    --accent: #0b6bcb;
    --accent-soft: rgba(11, 107, 203, 0.11);
    --green: #16794f;
    --green-soft: rgba(22, 121, 79, 0.12);
    --red: #b42318;
    --red-soft: rgba(180, 35, 24, 0.11);
    --amber: #9a5b13;
    --amber-soft: rgba(154, 91, 19, 0.12);
    --mono: "SF Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif;
    --radius: 10px;
  }

  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0e1015;
      --surface: #161a22;
      --surface-2: #1f242f;
      --border: #2c3240;
      --text: #edf0f5;
      --muted: #98a2b3;
      --accent: #53a5ff;
      --accent-soft: rgba(83, 165, 255, 0.15);
      --green: #3ccb7f;
      --green-soft: rgba(60, 203, 127, 0.15);
      --red: #f97066;
      --red-soft: rgba(249, 112, 102, 0.15);
      --amber: #fdb022;
      --amber-soft: rgba(253, 176, 34, 0.15);
    }
  }

  * { box-sizing: border-box; }
  html, body {
    margin: 0;
    padding: 0;
    height: 100%;
    width: 100%;
    overflow: hidden;
    font-family: var(--sans);
    background: var(--bg);
    color: var(--text);
    font-size: 14px;
    line-height: 1.55;
  }

  .app {
    display: grid;
    grid-template-rows: 50px minmax(0, 1fr);
    height: 100vh;
    width: 100vw;
    overflow: hidden;
  }

  .topbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 18px;
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    gap: 12px;
    min-width: 0;
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 10px;
    font-weight: 600;
    font-size: 14px;
    letter-spacing: -0.01em;
    white-space: nowrap;
  }

  .conn-pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 11.5px;
    font-weight: 600;
    padding: 2px 9px;
    border-radius: 999px;
    background: var(--surface-2);
    color: var(--muted);
  }
  .conn-pill.live { background: var(--green-soft); color: var(--green); }
  .conn-pill.offline { background: var(--red-soft); color: var(--red); }

  .controls {
    display: flex;
    align-items: center;
    gap: 14px;
    font-size: 12px;
    color: var(--muted);
    white-space: nowrap;
  }
  .controls label {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    cursor: pointer;
    user-select: none;
  }

  .workspace {
    display: grid;
    grid-template-columns: 264px minmax(0, 1fr);
    min-height: 0;
    min-width: 0;
    overflow: hidden;
  }

  .sidebar {
    background: var(--surface);
    border-right: 1px solid var(--border);
    overflow-y: auto;
    padding: 10px;
    min-width: 0;
  }

  .sidebar-label {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted);
    padding: 4px 8px 6px;
  }

  .run-item {
    border: 1px solid transparent;
    border-radius: 8px;
    padding: 9px 10px;
    margin-bottom: 4px;
    cursor: pointer;
    display: flex;
    flex-direction: column;
    gap: 4px;
    background: transparent;
    text-align: left;
    color: inherit;
    font: inherit;
    width: 100%;
  }
  .run-item:hover { background: var(--surface-2); }
  .run-item.selected {
    background: var(--accent-soft);
    border-color: var(--accent);
  }

  .run-item-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 6px;
    font-weight: 600;
    font-size: 13px;
  }

  .run-item-meta {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 6px;
    font-size: 11.5px;
    color: var(--muted);
    min-width: 0;
  }

  .phase-dots {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    flex-shrink: 0;
  }

  .mini-pill {
    font-size: 10.5px;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: 999px;
    background: var(--surface-2);
    color: var(--muted);
  }
  .mini-pill.running { background: var(--accent-soft); color: var(--accent); }
  .mini-pill.queued { background: var(--amber-soft); color: var(--amber); }
  .mini-pill.success { background: var(--green-soft); color: var(--green); }
  .mini-pill.failure { background: var(--red-soft); color: var(--red); }
  .mini-pill.skipped { background: var(--surface-2); color: var(--muted); opacity: 0.65; }

  .main {
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr) auto;
    min-height: 0;
    min-width: 0;
    overflow: hidden;
  }

  .run-header {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    padding: 11px 22px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    flex-wrap: wrap;
    min-width: 0;
  }

  .run-title {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;
    min-width: 0;
  }
  .run-title h1 {
    margin: 0;
    font-size: 15.5px;
    font-weight: 650;
    letter-spacing: -0.01em;
  }

  .chip {
    font-size: 11.5px;
    font-weight: 500;
    padding: 2px 8px;
    border-radius: 6px;
    background: var(--surface-2);
    color: var(--muted);
    font-family: var(--mono);
  }

  .header-links {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .btn-link {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-size: 12px;
    font-weight: 500;
    color: var(--accent);
    text-decoration: none;
    padding: 4px 10px;
    border-radius: 6px;
    border: 1px solid var(--border);
    background: var(--surface);
  }
  .btn-link:hover { background: var(--surface-2); }

  .tabs-bar {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px 22px 0;
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    overflow-x: auto;
    min-width: 0;
  }

  .tab-btn {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 9px 14px;
    border: none;
    border-bottom: 2px solid transparent;
    background: transparent;
    color: var(--muted);
    font: inherit;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    white-space: nowrap;
    flex-shrink: 0;
  }
  .tab-btn:hover { color: var(--text); }
  .tab-btn.active {
    color: var(--text);
    border-bottom-color: var(--accent);
  }

  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--muted);
    flex-shrink: 0;
  }
  .dot.running {
    background: var(--accent);
    box-shadow: 0 0 0 0 var(--accent);
    animation: pulse 1.5s infinite;
  }
  .dot.queued { background: var(--amber); }
  .dot.success { background: var(--green); }
  .dot.failure { background: var(--red); }
  .dot.skipped { background: var(--muted); opacity: 0.45; }

  @keyframes pulse {
    0% { box-shadow: 0 0 0 0 rgba(83, 165, 255, 0.55); }
    70% { box-shadow: 0 0 0 7px rgba(83, 165, 255, 0); }
    100% { box-shadow: 0 0 0 0 rgba(83, 165, 255, 0); }
  }

  .harness-tag {
    font-size: 11px;
    font-weight: 600;
    padding: 1px 7px;
    border-radius: 999px;
    background: var(--surface-2);
    color: var(--muted);
  }
  .harness-tag.codex, .harness-tag.sol { background: var(--green-soft); color: var(--green); }
  .harness-tag.antigravity, .harness-tag.neon { background: var(--accent-soft); color: var(--accent); }
  .harness-tag.hydrogen { background: rgba(20, 184, 166, 0.14); color: #5eead4; }
  .harness-tag.opus { background: rgba(249, 115, 22, 0.16); color: #fb923c; }

  .tab-meta {
    font-size: 11.5px;
    font-weight: 400;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }

  /* Normal block flow prevents flexbox from shrinking collapsed <details> cards into slivers. */
  .timeline {
    display: block;
    overflow-y: auto;
    overflow-x: hidden;
    min-width: 0;
    min-height: 0;
    padding: 18px 24px 36px;
  }

  .timeline-inner {
    max-width: 960px;
    margin: 0 auto;
    min-width: 0;
  }

  .timeline-inner > * {
    margin-bottom: 10px;
    min-width: 0;
    max-width: 100%;
  }
  .timeline-inner > *:last-child {
    margin-bottom: 0;
  }

  .session-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 10px 14px;
    font-size: 12.5px;
  }
  .session-card summary {
    cursor: pointer;
    color: var(--muted);
    font-weight: 500;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    list-style: none;
  }
  .session-card summary::-webkit-details-marker { display: none; }
  .session-kv {
    margin-top: 10px;
    display: grid;
    grid-template-columns: 104px minmax(0, 1fr);
    gap: 6px 10px;
    font-size: 12px;
  }
  .session-kv .k { color: var(--muted); }
  .session-kv .v { font-family: var(--mono); overflow-wrap: anywhere; }

  .prompt-box {
    margin-top: 10px;
    padding: 10px 12px;
    background: var(--surface-2);
    border-radius: 8px;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    font-size: 12.5px;
    line-height: 1.5;
  }

  .event-msg {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 14px 16px;
    overflow-wrap: anywhere;
  }
  .event-msg-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 6px;
    font-size: 11.5px;
    font-weight: 600;
    color: var(--muted);
  }
  .event-msg .md p { margin: 0 0 8px; }
  .event-msg .md p:last-child { margin-bottom: 0; }
  .event-msg .md h1, .event-msg .md h2, .event-msg .md h3 {
    margin: 10px 0 6px;
    font-size: 14.5px;
  }
  .event-msg .md h1:first-child, .event-msg .md h2:first-child, .event-msg .md h3:first-child {
    margin-top: 0;
  }
  .event-msg .md ul, .event-msg .md ol { margin: 6px 0; padding-left: 20px; }
  .event-msg .md code {
    font-family: var(--mono);
    font-size: 12.5px;
    background: var(--surface-2);
    padding: 1px 5px;
    border-radius: 4px;
  }
  .event-msg .md pre {
    background: var(--surface-2);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 10px 12px;
    overflow-x: auto;
    margin: 8px 0;
  }
  .event-msg .md pre code {
    background: none;
    padding: 0;
    font-size: 12px;
  }
  .event-msg .md a { color: var(--accent); }

  .event-tool {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
  }
  .event-tool summary {
    padding: 9px 13px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    font-family: var(--mono);
    font-size: 12px;
    list-style: none;
    border-radius: var(--radius);
    min-width: 0;
  }
  .event-tool[open] summary {
    border-bottom-left-radius: 0;
    border-bottom-right-radius: 0;
  }
  .event-tool summary::-webkit-details-marker { display: none; }
  .event-tool summary:hover { background: var(--surface-2); }

  .tool-left {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
    flex: 1;
  }
  .tool-title {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-width: 0;
  }
  .tool-right {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    flex-shrink: 0;
  }
  .status-badge {
    font-size: 11px;
    font-weight: 600;
    padding: 1px 7px;
    border-radius: 999px;
    background: var(--surface-2);
    color: var(--muted);
  }
  .status-badge.ok { background: var(--green-soft); color: var(--green); }
  .status-badge.fail { background: var(--red-soft); color: var(--red); }
  .status-badge.run { background: var(--accent-soft); color: var(--accent); }

  .tool-body {
    border-top: 1px solid var(--border);
    background: var(--surface-2);
    padding: 10px 13px;
    font-family: var(--mono);
    font-size: 11.5px;
    line-height: 1.5;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    max-height: 440px;
    overflow-y: auto;
    border-bottom-left-radius: var(--radius);
    border-bottom-right-radius: var(--radius);
  }
  .tool-section-label {
    font-family: var(--sans);
    font-size: 10.5px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted);
    margin: 0 0 4px;
  }
  .tool-section + .tool-section {
    margin-top: 10px;
    padding-top: 10px;
    border-top: 1px solid var(--border);
  }

  .event-reasoning {
    background: var(--surface-2);
    border: 1px dashed var(--border);
    border-radius: var(--radius);
    font-size: 12.5px;
    color: var(--muted);
  }
  .event-reasoning summary {
    padding: 8px 13px;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 8px;
    list-style: none;
    min-width: 0;
  }
  .event-reasoning summary::-webkit-details-marker { display: none; }
  .reasoning-label {
    font-weight: 600;
    flex-shrink: 0;
  }
  .reasoning-preview {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-width: 0;
    flex: 1;
    opacity: 0.85;
  }
  .reasoning-body {
    padding: 2px 13px 11px;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    line-height: 1.5;
  }

  .event-error {
    background: var(--red-soft);
    border: 1px solid var(--red);
    color: var(--red);
    border-radius: var(--radius);
    padding: 10px 14px;
    font-family: var(--mono);
    font-size: 12.5px;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }

  .event-notice {
    background: var(--amber-soft);
    border: 1px solid var(--border);
    color: var(--amber);
    border-radius: var(--radius);
    padding: 8px 13px;
    font-family: var(--mono);
    font-size: 12px;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }

  .footer {
    background: var(--surface);
    border-top: 1px solid var(--border);
    padding: 8px 22px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    font-size: 12px;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
    min-width: 0;
  }
  .footer-left {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }
  .jump-btn {
    border: 1px solid var(--border);
    background: var(--surface-2);
    color: var(--text);
    border-radius: 6px;
    padding: 3px 9px;
    font-size: 12px;
    cursor: pointer;
  }
  .empty-state {
    margin: 48px auto;
    text-align: center;
    max-width: 440px;
    color: var(--muted);
    padding: 24px;
  }
  .empty-state h2 {
    margin: 0 0 8px;
    font-size: 16px;
    color: var(--text);
  }

  @media (max-width: 820px) {
    .workspace { grid-template-columns: minmax(0, 1fr); grid-template-rows: 160px minmax(0, 1fr); }
    .sidebar { border-right: none; border-bottom: 1px solid var(--border); }
  }
</style>
</head>
<body>
<div class="app">
  <header class="topbar">
    <div class="brand">
      <span>Clinical Agent Monitor</span>
      <span id="connPill" class="conn-pill">Connecting…</span>
    </div>
    <div class="controls">
      <label><input type="checkbox" id="autoFollow" checked /> Auto-follow live</label>
      <label><input type="checkbox" id="showReasoning" checked /> Show reasoning</label>
      <label><input type="checkbox" id="expandTools" /> Expand tools</label>
    </div>
  </header>

  <div class="workspace">
    <aside class="sidebar" id="sidebar"></aside>
    <main class="main" id="main">
      <div class="empty-state">
        <h2>Waiting for agent runs</h2>
        <p>Comment <code>/review</code>, <code>/address</code>, or <code>/ask</code> on a PR to watch the loop live.</p>
      </div>
    </main>
  </div>
</div>

<script>
const state = {
  snapshot: { runs: [] },
  selectedRunID: null,
  selectedPhase: null,
  manualPhasePin: false,
  stickToBottom: true,
  expandedIDs: new Set(),
  collapsedIDs: new Set(),
  lastRenderedKey: "",
};

const el = (id) => document.getElementById(id);

function escapeHTML(str) {
  return String(str ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function renderMarkdown(md) {
  if (!md) return "";
  const lines = String(md).replace(/\r\n/g, "\n").split("\n");
  let html = "";
  let inCode = false;
  let codeLines = [];
  let inList = false;

  const flushList = () => {
    if (inList) { html += "</ul>"; inList = false; }
  };

  const inline = (text) => {
    let out = escapeHTML(text);
    out = out.replace(/`([^`]+)`/g, "<code>$1</code>");
    out = out.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noreferrer">$1</a>');
    out = out.replace(/\[([^\]]+)\]\((file:\/\/[^\s)]+)\)/g, '<code title="$2">$1</code>');
    out = out.replace(/(^|[\s(])(https?:\/\/[^\s<)]+)/g, '$1<a href="$2" target="_blank" rel="noreferrer">$2</a>');
    out = out.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    return out;
  };

  for (const line of lines) {
    if (line.startsWith("```")) {
      flushList();
      if (!inCode) {
        inCode = true;
        codeLines = [];
      } else {
        html += `<pre><code>${escapeHTML(codeLines.join("\n"))}</code></pre>`;
        inCode = false;
      }
      continue;
    }
    if (inCode) {
      codeLines.push(line);
      continue;
    }
    if (/^\s*[-*]\s+/.test(line)) {
      if (!inList) { html += "<ul>"; inList = true; }
      html += `<li>${inline(line.replace(/^\s*[-*]\s+/, ""))}</li>`;
      continue;
    }
    flushList();
    if (/^###\s+/.test(line)) {
      html += `<h3>${inline(line.replace(/^###\s+/, ""))}</h3>`;
    } else if (/^##\s+/.test(line)) {
      html += `<h2>${inline(line.replace(/^##\s+/, ""))}</h2>`;
    } else if (/^#\s+/.test(line)) {
      html += `<h1>${inline(line.replace(/^#\s+/, ""))}</h1>`;
    } else if (line.trim() !== "") {
      html += `<p>${inline(line)}</p>`;
    }
  }
  if (inCode) {
    html += `<pre><code>${escapeHTML(codeLines.join("\n"))}</code></pre>`;
  }
  flushList();
  return html;
}

function formatDuration(startedAt, completedAt) {
  if (!startedAt) return "";
  const start = Date.parse(startedAt);
  if (Number.isNaN(start)) return "";
  const end = completedAt ? Date.parse(completedAt) : Date.now();
  const seconds = Math.max(0, Math.floor((end - start) / 1000));
  if (seconds < 60) return `${seconds}s`;
  const mins = Math.floor(seconds / 60);
  const rem = seconds % 60;
  return `${mins}m ${String(rem).padStart(2, "0")}s`;
}

function formatTokens(usage) {
  if (!usage) return "";
  const total = (usage.inputTokens || 0) + (usage.outputTokens || 0);
  if (!total) return "";
  if (total >= 1000) return `${(total / 1000).toFixed(1)}k tok`;
  return `${total} tok`;
}

function phaseDotClass(phase) {
  if (phase.status === "running") return "running";
  if (phase.status === "queued") return "queued";
  if (phase.conclusion === "success") return "success";
  if (phase.conclusion === "skipped") return "skipped";
  if (phase.conclusion === "failure" || phase.conclusion === "cancelled") return "failure";
  return "";
}

function harnessLabel(harness) {
  if (harness === "codex") return "Codex";
  if (harness === "antigravity") return "Antigravity";
  return harness || "Agent";
}

function modelShortLabel(model) {
  if (!model) return "";
  const lower = String(model).toLowerCase();
  if (lower.startsWith("gpt-6.1-sol")) return "6.1 Sol";
  if (lower.startsWith("gemini-4-neon")) return "4 Neon";
  if (lower.startsWith("gemini-4-hydrogen")) return "4 Hydrogen";
  if (lower.startsWith("claude-opus-5-5") || lower.startsWith("claude-opus")) return "Opus 5.5";
  return String(model);
}

function agentBadgeLabel(harness, model) {
  const h = harnessLabel(harness);
  const m = modelShortLabel(model);
  return m ? `${h} · ${m}` : h;
}

function agentBadgeClass(harness, model) {
  const lower = String(model || "").toLowerCase();
  if (lower.startsWith("gpt-6.1-sol")) return "sol";
  if (lower.startsWith("gemini-4-neon")) return "neon";
  if (lower.startsWith("gemini-4-hydrogen")) return "hydrogen";
  if (lower.startsWith("claude-opus")) return "opus";
  return harness || "";
}

function pickInitialPhase(run) {
  if (!run || !run.phases.length) return null;
  const active = run.phases.find((p) => p.status === "running");
  if (active) return active.phase;
  const nonSkipped = [...run.phases].reverse().find((p) => p.status === "completed" && p.conclusion !== "skipped");
  return (nonSkipped || run.phases[0]).phase;
}

function syncSelection() {
  const runs = state.snapshot.runs || [];
  if (!runs.length) {
    state.selectedRunID = null;
    state.selectedPhase = null;
    return;
  }

  const autoFollow = el("autoFollow").checked;
  const liveRun = runs.find((r) => r.isLive);

  if (autoFollow && liveRun && state.selectedRunID !== liveRun.runID) {
    state.selectedRunID = liveRun.runID;
    state.selectedPhase = pickInitialPhase(liveRun);
    state.manualPhasePin = false;
    state.stickToBottom = true;
  }

  let run = runs.find((r) => r.runID === state.selectedRunID);
  if (!run) {
    run = liveRun || runs[0];
    state.selectedRunID = run.runID;
    state.selectedPhase = pickInitialPhase(run);
    state.manualPhasePin = false;
  }

  if (autoFollow && !state.manualPhasePin) {
    const runningPhase = run.phases.find((p) => p.status === "running");
    if (runningPhase && runningPhase.phase !== state.selectedPhase) {
      state.selectedPhase = runningPhase.phase;
      state.stickToBottom = true;
    }
  }

  if (!run.phases.some((p) => p.phase === state.selectedPhase)) {
    state.selectedPhase = pickInitialPhase(run);
  }
}

function renderSidebar() {
  const sidebar = el("sidebar");
  const runs = state.snapshot.runs || [];
  if (!runs.length) {
    sidebar.innerHTML = '<div class="sidebar-label">Runs</div><div style="padding:8px;color:var(--muted);font-size:12px;">No recorded runs yet.</div>';
    return;
  }

  let html = '<div class="sidebar-label">Runs</div>';
  for (const run of runs) {
    const selected = run.runID === state.selectedRunID ? "selected" : "";
    const title = run.prNumber ? `PR #${run.prNumber}` : `Run ${run.runID}`;
    const kind = run.kind === "ask" ? "Ask" : "Review Loop";
    const pills = run.phases.map((p) => {
      const letter = p.phase.startsWith("review") ? "R" : p.phase.startsWith("address") ? "A" : "Q";
      const badge = agentBadgeLabel(p.harness, p.model);
      return `<span class="mini-pill ${phaseDotClass(p)}" title="${escapeHTML(p.label)} (${escapeHTML(badge)}): ${p.conclusion || p.status}">${letter}</span>`;
    }).join("");
    const sub = run.prBranch || (run.source === "local-sessions" ? "Local sessions" : run.runID);
    html += `
      <button class="run-item ${selected}" data-run-id="${escapeHTML(run.runID)}">
        <div class="run-item-top">
          <span>${escapeHTML(title)}</span>
          <span class="phase-dots">${pills}</span>
        </div>
        <div class="run-item-meta">
          <span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHTML(sub)}</span>
          <span style="flex-shrink:0;">${escapeHTML(kind)}</span>
        </div>
      </button>`;
  }
  sidebar.innerHTML = html;

  for (const btn of sidebar.querySelectorAll(".run-item")) {
    btn.addEventListener("click", () => {
      const id = btn.getAttribute("data-run-id");
      const run = runs.find((r) => r.runID === id);
      state.selectedRunID = id;
      state.selectedPhase = pickInitialPhase(run);
      state.manualPhasePin = false;
      state.stickToBottom = true;
      state.lastRenderedKey = "";
      renderAll();
    });
  }
}

function renderEventCard(ev, harness, model) {
  const showReasoning = el("showReasoning").checked;
  const expandTools = el("expandTools").checked;

  if (ev.kind === "reasoning") {
    if (!showReasoning) return "";
    const open = state.expandedIDs.has(ev.id) ? "open" : "";
    const preview = String(ev.text || "").split("\n")[0].trim();
    return `
      <details class="event-reasoning" data-ev-id="${escapeHTML(ev.id)}" ${open}>
        <summary>
          <span class="reasoning-label">Thinking</span>
          <span class="reasoning-preview">${escapeHTML(preview)}</span>
        </summary>
        <div class="reasoning-body">${escapeHTML(ev.text || "")}</div>
      </details>`;
  }

  if (ev.kind === "message") {
    return `
      <div class="event-msg">
        <div class="event-msg-head">
          <span>${escapeHTML(agentBadgeLabel(harness, model))}</span>
        </div>
        <div class="md">${renderMarkdown(ev.text || "")}</div>
      </div>`;
  }

  if (ev.kind === "error") {
    return `<div class="event-error">${escapeHTML(ev.text || ev.title || "Error")}</div>`;
  }

  if (ev.kind === "notice") {
    return `<div class="event-notice">${escapeHTML(ev.text || "")}</div>`;
  }

  if (ev.kind === "command" || ev.kind === "tool" || ev.kind === "file_change") {
    const isRunning = ev.status === "running";
    const defaultOpen = expandTools || isRunning;
    const isOpen = state.expandedIDs.has(ev.id) || (defaultOpen && !state.collapsedIDs.has(ev.id));

    let badgeText = ev.status;
    let badgeClass = "";
    if (isRunning) {
      badgeText = "running…";
      badgeClass = "run";
    } else if (ev.exitCode !== null && ev.exitCode !== undefined) {
      badgeText = `exit ${ev.exitCode}`;
      badgeClass = ev.exitCode === 0 ? "ok" : "fail";
    } else if (ev.durationSeconds) {
      badgeText = `${ev.durationSeconds.toFixed(1)}s`;
      badgeClass = ev.status === "failed" ? "fail" : "ok";
    } else {
      badgeClass = ev.status === "failed" ? "fail" : "ok";
    }

    let bodyHTML = "";
    if (ev.text || ev.output) {
      const sections = [];
      if (ev.text) {
        const label = ev.kind === "command" ? "Command" : ev.kind === "file_change" ? "Changes" : "Input";
        sections.push(`<div class="tool-section"><div class="tool-section-label">${label}</div>${escapeHTML(ev.text)}</div>`);
      }
      if (ev.output) {
        sections.push(`<div class="tool-section"><div class="tool-section-label">Output</div>${escapeHTML(ev.output)}</div>`);
      }
      bodyHTML = `<div class="tool-body">${sections.join("")}</div>`;
    }

    return `
      <details class="event-tool" data-ev-id="${escapeHTML(ev.id)}" ${isOpen ? "open" : ""}>
        <summary>
          <span class="tool-left">
            <span class="dot ${isRunning ? "running" : ev.status === "failed" ? "failure" : "success"}"></span>
            <span class="tool-title">${escapeHTML(ev.title || ev.kind)}</span>
          </span>
          <span class="tool-right">
            <span class="status-badge ${badgeClass}">${escapeHTML(badgeText)}</span>
          </span>
        </summary>
        ${bodyHTML}
      </details>`;
  }

  return "";
}

function renderMain(force = false) {
  const main = el("main");
  const runs = state.snapshot.runs || [];
  const run = runs.find((r) => r.runID === state.selectedRunID);
  if (!run) {
    state.lastRenderedKey = "";
    main.innerHTML = `
      <div class="empty-state">
        <h2>Waiting for agent runs</h2>
        <p>Comment <code>/review</code>, <code>/address</code>, or <code>/ask</code> on a PR to watch the loop live.</p>
      </div>`;
    return;
  }

  const phase = run.phases.find((p) => p.phase === state.selectedPhase) || run.phases[0];
  const renderKey = JSON.stringify([
    run.runID,
    run.updatedAt,
    phase ? phase.phase : "",
    phase ? phase.status : "",
    phase ? phase.model : "",
    phase ? phase.updatedAt : "",
    phase ? phase.events.length : 0,
    el("showReasoning").checked,
    el("expandTools").checked,
  ]);
  if (!force && renderKey === state.lastRenderedKey) {
    updateLiveTimers();
    return;
  }
  state.lastRenderedKey = renderKey;

  const prevTimeline = main.querySelector("#timeline");
  const prevScrollTop = prevTimeline ? prevTimeline.scrollTop : 0;

  const titleText = run.prNumber ? `PR #${run.prNumber}` : `Run ${run.runID}`;
  const repoURL = run.repository ? `https://github.com/${run.repository}` : null;
  const prURL = repoURL && run.prNumber ? `${repoURL}/pull/${run.prNumber}` : null;

  const tabsHTML = run.phases.map((p) => {
    const active = phase && p.phase === phase.phase ? "active" : "";
    const dotClass = phaseDotClass(p);
    const dur = formatDuration(p.startedAt, p.completedAt);
    const tok = formatTokens(p.usage);
    const timerAttr = p.status === "running" && p.startedAt ? `data-live-start="${escapeHTML(p.startedAt)}"` : "";
    const badgeClass = agentBadgeClass(p.harness, p.model);
    const badgeLabel = agentBadgeLabel(p.harness, p.model);
    return `
      <button class="tab-btn ${active}" data-phase="${escapeHTML(p.phase)}">
        <span class="dot ${dotClass}"></span>
        <span>${escapeHTML(p.label)}</span>
        <span class="harness-tag ${escapeHTML(badgeClass)}">${escapeHTML(badgeLabel)}</span>
        <span class="tab-meta">
          <span ${timerAttr}>${escapeHTML(dur)}</span>${dur && tok ? " · " : ""}${escapeHTML(tok)}
        </span>
      </button>`;
  }).join("");

  let timelineHTML = "";
  let footerHTML = "";

  if (phase) {
    const sessionKey = `session-${run.runID}-${phase.phase}`;
    const sessionOpen = state.expandedIDs.has(sessionKey) ? "open" : "";
    const phaseBadge = agentBadgeLabel(phase.harness, phase.model);
    timelineHTML += `
      <details class="session-card" data-ev-id="${escapeHTML(sessionKey)}" ${sessionOpen}>
        <summary>
          <span>${escapeHTML(phaseBadge)}${phase.botLogin ? ` · ${escapeHTML(phase.botLogin)}` : ""}${phase.model ? ` · ${escapeHTML(phase.model)}` : ""}</span>
          <span class="tab-meta">Session details ▾</span>
        </summary>
        <div class="session-kv">
          <div class="k">Status</div><div class="v">${escapeHTML(phase.conclusion || phase.status)}</div>
          ${phase.sessionID ? `<div class="k">Session ID</div><div class="v">${escapeHTML(phase.sessionID)}</div>` : ""}
          ${phase.model ? `<div class="k">Model</div><div class="v">${escapeHTML(phase.model)}</div>` : ""}
          ${phase.effort ? `<div class="k">Effort</div><div class="v">${escapeHTML(phase.effort)}</div>` : ""}
          ${phase.worktreePath ? `<div class="k">Worktree</div><div class="v">${escapeHTML(phase.worktreePath)}</div>` : ""}
        </div>
        ${phase.prompt ? `<div class="prompt-box">${escapeHTML(phase.prompt)}</div>` : ""}
      </details>`;

    if (!phase.events.length) {
      const waitMsg =
        phase.status === "queued"
          ? `${phase.label} is queued and waiting to start…`
          : phase.status === "running"
          ? `${phaseBadge} started. Waiting for first output…`
          : phase.conclusion === "skipped"
          ? `${phase.label} was skipped.`
          : "No streamed events captured for this phase.";
      timelineHTML += `<div class="empty-state"><p>${escapeHTML(waitMsg)}</p></div>`;
    } else {
      timelineHTML += phase.events.map((ev) => renderEventCard(ev, phase.harness, phase.model)).join("");
    }

    const dur = formatDuration(phase.startedAt, phase.completedAt);
    const statusText =
      phase.status === "running"
        ? `${phaseBadge} is running…`
        : phase.status === "queued"
        ? "Queued"
        : `Completed (${phase.conclusion || "done"})`;
    const timerAttr = phase.status === "running" && phase.startedAt ? `data-live-start="${escapeHTML(phase.startedAt)}"` : "";
    const u = phase.usage || {};
    const tokenBreakdown = `In ${(u.inputTokens || 0).toLocaleString()} (cached ${(u.cachedInputTokens || 0).toLocaleString()}) · Out ${(u.outputTokens || 0).toLocaleString()}${u.thinkingTokens ? ` · Think ${u.thinkingTokens.toLocaleString()}` : ""}`;
    footerHTML = `
      <div class="footer-left">
        <span class="dot ${phaseDotClass(phase)}"></span>
        <span>${escapeHTML(statusText)}${dur ? ` · <span ${timerAttr}>${escapeHTML(dur)}</span>` : ""}</span>
      </div>
      <div style="display:flex;align-items:center;gap:10px;flex-shrink:0;">
        <span>${escapeHTML(tokenBreakdown)}</span>
        <button class="jump-btn" id="jumpLatest" style="display:${state.stickToBottom ? "none" : "inline-block"};">Follow latest ↓</button>
      </div>`;
  }

  main.innerHTML = `
    <div class="run-header">
      <div class="run-title">
        <h1>${escapeHTML(titleText)}</h1>
        ${run.prBranch ? `<span class="chip">${escapeHTML(run.prBranch)}</span>` : ""}
        ${run.prHeadSHA ? `<span class="chip">${escapeHTML(run.prHeadSHA.slice(0, 7))}</span>` : ""}
        ${run.source === "local-sessions" ? '<span class="chip">Local sessions</span>' : ""}
      </div>
      <div class="header-links">
        ${prURL ? `<a class="btn-link" href="${escapeHTML(prURL)}" target="_blank" rel="noreferrer">Open PR ↗</a>` : ""}
        ${run.runURL ? `<a class="btn-link" href="${escapeHTML(run.runURL)}" target="_blank" rel="noreferrer">GitHub Run ↗</a>` : ""}
      </div>
    </div>
    <div class="tabs-bar">${tabsHTML}</div>
    <div class="timeline" id="timeline"><div class="timeline-inner">${timelineHTML}</div></div>
    <div class="footer">${footerHTML}</div>
  `;

  for (const btn of main.querySelectorAll(".tab-btn")) {
    btn.addEventListener("click", () => {
      state.selectedPhase = btn.getAttribute("data-phase");
      state.manualPhasePin = true;
      state.stickToBottom = true;
      renderMain(true);
    });
  }

  for (const details of main.querySelectorAll("details[data-ev-id]")) {
    details.addEventListener("toggle", () => {
      const id = details.getAttribute("data-ev-id");
      if (details.open) {
        state.expandedIDs.add(id);
        state.collapsedIDs.delete(id);
      } else {
        state.expandedIDs.delete(id);
        state.collapsedIDs.add(id);
      }
    });
  }

  const timeline = el("timeline");
  const jumpBtn = el("jumpLatest");
  if (timeline) {
    if (state.stickToBottom) {
      timeline.scrollTop = timeline.scrollHeight;
    } else {
      timeline.scrollTop = prevScrollTop;
    }
    timeline.addEventListener("scroll", () => {
      const distance = timeline.scrollHeight - timeline.scrollTop - timeline.clientHeight;
      state.stickToBottom = distance < 48;
      if (jumpBtn) {
        jumpBtn.style.display = state.stickToBottom ? "none" : "inline-block";
      }
    });
  }

  if (jumpBtn && timeline) {
    jumpBtn.addEventListener("click", () => {
      state.stickToBottom = true;
      timeline.scrollTop = timeline.scrollHeight;
      jumpBtn.style.display = "none";
    });
  }
}

function updateLiveTimers() {
  for (const node of document.querySelectorAll("[data-live-start]")) {
    const start = node.getAttribute("data-live-start");
    if (start) {
      node.textContent = formatDuration(start, null);
    }
  }
}

function renderAll(force = false) {
  syncSelection();
  renderSidebar();
  renderMain(force);
}

function connectSSE() {
  const pill = el("connPill");
  const source = new EventSource("/api/events");
  source.addEventListener("open", () => {
    pill.textContent = "Live";
    pill.className = "conn-pill live";
  });
  source.addEventListener("snapshot", (ev) => {
    try {
      state.snapshot = JSON.parse(ev.data);
      pill.textContent = "Live";
      pill.className = "conn-pill live";
      renderAll(false);
    } catch (err) {
      console.error(err);
    }
  });
  source.addEventListener("error", () => {
    pill.textContent = "Reconnecting…";
    pill.className = "conn-pill offline";
  });
}

el("autoFollow").addEventListener("change", () => renderAll(true));
el("showReasoning").addEventListener("change", () => renderMain(true));
el("expandTools").addEventListener("change", () => renderMain(true));

setInterval(updateLiveTimers, 1000);

fetch("/api/snapshot")
  .then((r) => r.json())
  .then((data) => {
    state.snapshot = data;
    renderAll(true);
  })
  .catch(() => {});

connectSSE();
</script>
</body>
</html>
"""#

// MARK: - CLI

private func runMonitorCLI() -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    var port: UInt16 = 4873
    var openBrowser = false
    var home = FileManager.default.homeDirectoryForCurrentUser.path
    var monitorDir = ProcessInfo.processInfo.environment["AGENT_MONITOR_DIR"]
        ?? "\(home)/.clinical-agent-monitor"

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--port":
            guard index + 1 < args.count, let parsed = UInt16(args[index + 1]) else {
                FileHandle.standardError.write(Data("Invalid or missing --port\n".utf8))
                return 2
            }
            port = parsed
            index += 2
        case "--monitor-dir":
            guard index + 1 < args.count else {
                FileHandle.standardError.write(Data("Missing --monitor-dir\n".utf8))
                return 2
            }
            monitorDir = args[index + 1]
            index += 2
        case "--home":
            guard index + 1 < args.count else {
                FileHandle.standardError.write(Data("Missing --home\n".utf8))
                return 2
            }
            home = args[index + 1]
            index += 2
        case "--open":
            openBrowser = true
            index += 1
        default:
            FileHandle.standardError.write(
                Data("Usage: agent_monitor.swift [--port 4873] [--monitor-dir PATH] [--open]\n".utf8)
            )
            return 2
        }
    }

    let codexSessionsDir = "\(home)/.codex/sessions"
    let agyBrainDir = "\(home)/.gemini/antigravity-cli/brain"
    let server = MonitorServer(
        port: port,
        monitorDirectory: monitorDir,
        codexSessionsDirectory: codexSessionsDir,
        agyBrainDirectory: agyBrainDir
    )
    do {
        try server.start(openBrowser: openBrowser)
        dispatchMain()
    } catch {
        FileHandle.standardError.write(Data("Failed to start monitor: \(error)\n".utf8))
        return 1
    }
}

#if !AGENT_MONITOR_TESTS
    _ = runMonitorCLI()
#endif
