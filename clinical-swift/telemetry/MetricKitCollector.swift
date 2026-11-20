import ClinicalModels
import Foundation
import MetricKit
import Synchronization

/// Parses Apple `MXDiagnosticPayload` JSON into flat telemetry entries with trimmed call stacks.
nonisolated enum MetricKitParser {
    private static let maxThreads = 8
    private static let maxFramesPerThread = 24
    private static let maxDetailsBytes = 16 * 1024

    private struct DiagnosticSection {
        let key: String
        let name: String
        let level: TelemetryLevel
    }

    private static let sections: [DiagnosticSection] = [
        DiagnosticSection(key: "crashDiagnostics", name: "metrickit_crash", level: .fault),
        DiagnosticSection(key: "hangDiagnostics", name: "metrickit_hang", level: .error),
        DiagnosticSection(
            key: "cpuExceptionDiagnostics", name: "metrickit_cpu_exception", level: .warning),
        DiagnosticSection(
            key: "diskWriteExceptionDiagnostics",
            name: "metrickit_disk_write_exception",
            level: .warning
        ),
    ]

    static func parseDiagnosticPayload(_ jsonData: Data) -> [TelemetryEntry] {
        guard
            let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return [] }

        var entries: [TelemetryEntry] = []
        let timeStampBegin = root["timeStampBegin"] as? String
        let timeStampEnd = root["timeStampEnd"] as? String

        for section in sections {
            guard let items = root[section.key] as? [[String: Any]] else { continue }
            for item in items {
                entries.append(
                    makeEntry(
                        item: item,
                        section: section,
                        timeStampBegin: timeStampBegin,
                        timeStampEnd: timeStampEnd
                    ))
            }
        }
        return entries
    }

    private static func makeEntry(
        item: [String: Any],
        section: DiagnosticSection,
        timeStampBegin: String?,
        timeStampEnd: String?
    ) -> TelemetryEntry {
        let meta = item["diagnosticMetaData"] as? [String: Any] ?? [:]
        let terminationReason = meta["terminationReason"] as? String
        let exceptionType = intValue(meta["exceptionType"])
        let exceptionCode = intValue(meta["exceptionCode"])
        let signal = intValue(meta["signal"])
        let hangDuration = meta["hangDuration"] as? String
        let totalCPUTime = meta["totalCPUTime"] as? String
        let totalWritesCaused = meta["totalWritesCaused"] as? String

        var summaryParts: [String] = []
        if let terminationReason, !terminationReason.isEmpty {
            summaryParts.append(terminationReason)
        }
        if let signal { summaryParts.append("signal=\(signal)") }
        if let exceptionType { summaryParts.append("exception=\(exceptionType)") }
        if let hangDuration { summaryParts.append("hang=\(hangDuration)") }
        if let totalCPUTime { summaryParts.append("cpu=\(totalCPUTime)") }
        if let totalWritesCaused { summaryParts.append("writes=\(totalWritesCaused)") }
        let message = summaryParts.isEmpty ? section.name : summaryParts.joined(separator: " ")

        var detailsObject: [String: Any] = [:]
        if let timeStampBegin { detailsObject["timeStampBegin"] = timeStampBegin }
        if let timeStampEnd { detailsObject["timeStampEnd"] = timeStampEnd }
        if let version = item["version"] as? String { detailsObject["version"] = version }
        if !meta.isEmpty { detailsObject["meta"] = meta }
        if let callStackTree = item["callStackTree"] as? [String: Any] {
            detailsObject["callStackTree"] = trimCallStackTree(callStackTree)
        }

        let detailsJSON = encodeCompactJSON(detailsObject)
        return TelemetryEntry(
            kind: .metric,
            level: section.level,
            category: .metrickit,
            name: section.name,
            message: message,
            errorCode: signal ?? exceptionCode ?? exceptionType,
            status: terminationReason,
            source: "metrickit",
            details: detailsJSON
        )
    }

    private static func trimCallStackTree(_ tree: [String: Any]) -> [String: Any] {
        var trimmed: [String: Any] = [:]
        if let perThread = tree["callStackPerThread"] as? Bool {
            trimmed["callStackPerThread"] = perThread
        }
        if let stacks = tree["callStacks"] as? [[String: Any]] {
            trimmed["callStacks"] = stacks.prefix(maxThreads).map { stack -> [String: Any] in
                var entry: [String: Any] = [:]
                if let attributed = stack["threadAttributed"] as? Bool {
                    entry["threadAttributed"] = attributed
                }
                if let rootFrames = stack["callStackRootFrames"] as? [[String: Any]] {
                    var flatFrames: [[String: Any]] = []
                    collectFrames(rootFrames, into: &flatFrames, limit: maxFramesPerThread)
                    entry["frames"] = flatFrames
                }
                return entry
            }
        }
        return trimmed
    }

    private static func collectFrames(
        _ frames: [[String: Any]],
        into result: inout [[String: Any]],
        limit: Int
    ) {
        for frame in frames {
            guard result.count < limit else { return }
            var compact: [String: Any] = [:]
            if let binaryName = frame["binaryName"] as? String {
                compact["binaryName"] = binaryName
            }
            if let binaryUUID = frame["binaryUUID"] as? String {
                compact["binaryUUID"] = binaryUUID
            }
            if let offset = frame["offsetIntoBinaryTextSegment"] {
                compact["offset"] = offset
            }
            if let address = frame["address"] {
                compact["address"] = address
            }
            if !compact.isEmpty {
                result.append(compact)
            }
            if let subFrames = frame["subFrames"] as? [[String: Any]], !subFrames.isEmpty {
                collectFrames(subFrames, into: &result, limit: limit)
            }
        }
    }

    private static func encodeCompactJSON(_ object: [String: Any]) -> String? {
        guard
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else { return nil }
        if string.utf8.count <= maxDetailsBytes {
            return string
        }
        return TelemetryRecord.truncateSQL(string, maxBytes: maxDetailsBytes)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

/// Subscribes to Apple MetricKit diagnostic payloads and forwards summaries into telemetry.
nonisolated final class MetricKitCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable
{
    private let record: @Sendable (TelemetryEntry) -> Void
    private let isRegistered = Mutex(false)

    init(record: @escaping @Sendable (TelemetryEntry) -> Void) {
        self.record = record
        super.init()
    }

    deinit {
        let shouldRemove = isRegistered.withLock { registered -> Bool in
            guard registered else { return false }
            registered = false
            return true
        }
        if shouldRemove {
            MXMetricManager.shared.remove(self)
        }
    }

    func start() {
        let shouldAdd = isRegistered.withLock { registered -> Bool in
            guard !registered else { return false }
            registered = true
            return true
        }
        if shouldAdd {
            MXMetricManager.shared.add(self)
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let entries = MetricKitParser.parseDiagnosticPayload(payload.jsonRepresentation())
            for entry in entries {
                record(entry)
            }
        }
    }
}
