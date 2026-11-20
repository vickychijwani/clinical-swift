import ClinicalModels
import Darwin
import Foundation
import OSLog
import Synchronization

/// Static device and bundle context attached to every telemetry record.
nonisolated struct TelemetryDeviceContext: Equatable, Sendable {
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let deviceModel: String

    static func current(bundle: Bundle = .main) -> Self {
        let appVersion =
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildNumber =
            bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        return Self(
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            deviceModel: hardwareModel()
        )
    }

    private static func hardwareModel() -> String {
        #if targetEnvironment(simulator)
            if let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
                !model.isEmpty
            {
                return model
            }
        #endif
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: pointer.pointee)) {
                String(cString: $0)
            }
        }
    }
}

/// Runtime process and environment identifiers shared by the app and widget extension.
nonisolated enum TelemetryRuntime {
    static let osLogSubsystem = "in.bitehaus.clinical"

    static var defaultEnvironment: TelemetryEnvironment {
        #if DEBUG || targetEnvironment(simulator)
            .dev
        #else
            .prod
        #endif
    }

    static var currentProcess: TelemetryProcess {
        #if WIDGET_EXTENSION
            .widget
        #else
            .app
        #endif
    }
}

/// Cross-process telemetry settings in App Group defaults and app-only upload status in standard defaults.
nonisolated final class TelemetrySettingsStore: @unchecked Sendable {
    static let verboseDuration: TimeInterval = 24 * 60 * 60

    private enum SharedKeys {
        static let deviceID = "telemetry.deviceID"
        static let verboseExpiresAt = "telemetry.verboseExpiresAt"
    }

    private enum StandardKeys {
        static let lastUploadedAt = "telemetry.lastUploadedAt"
        static let lastUploadError = "telemetry.lastUploadError"
    }

    // UserDefaults is thread-safe; the atomic cache avoids defaults reads on hot SQL callbacks.
    private let sharedDefaults: UserDefaults?
    private let standardDefaults: UserDefaults
    private let deviceIDLock = Mutex<Void>(())
    private let verboseExpiresAtBits: Atomic<UInt64>

    init(
        sharedDefaults: UserDefaults? = UserDefaults(
            suiteName: ClinicalSharedDatabase.appGroupIdentifier),
        standardDefaults: UserDefaults = .standard
    ) {
        self.sharedDefaults = sharedDefaults
        self.standardDefaults = standardDefaults
        let stored = sharedDefaults?.double(forKey: SharedKeys.verboseExpiresAt) ?? 0
        self.verboseExpiresAtBits = Atomic(stored.bitPattern)
    }

    /// Reads the shared device identifier without minting one. Used by the widget extension.
    func existingDeviceID() -> String? {
        sharedDefaults?.string(forKey: SharedKeys.deviceID)
    }

    /// Returns the shared device identifier, creating one on first app launch.
    func ensureDeviceID() -> String {
        deviceIDLock.withLock { _ in
            if let existing = sharedDefaults?.string(forKey: SharedKeys.deviceID), !existing.isEmpty {
                return existing
            }
            let created = UUID().uuidString.lowercased()
            sharedDefaults?.set(created, forKey: SharedKeys.deviceID)
            return created
        }
    }

    /// Fast-path check used on hot SQL trace callbacks. Clears expired values automatically.
    func isVerboseEnabled(at now: Date = .now) -> Bool {
        let expiresAt = Double(bitPattern: verboseExpiresAtBits.load(ordering: .relaxed))
        guard expiresAt > 0 else { return false }
        if now.timeIntervalSince1970 < expiresAt {
            return true
        }
        clearExpiredVerbose(expectedBits: expiresAt.bitPattern)
        return false
    }

    func verboseExpiresAt(at now: Date = .now) -> Date? {
        guard isVerboseEnabled(at: now) else { return nil }
        let expiresAt = Double(bitPattern: verboseExpiresAtBits.load(ordering: .relaxed))
        guard expiresAt > now.timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: expiresAt)
    }

    func setVerboseEnabled(_ enabled: Bool, now: Date = .now) {
        if enabled {
            let expiry = now.addingTimeInterval(Self.verboseDuration).timeIntervalSince1970
            verboseExpiresAtBits.store(expiry.bitPattern, ordering: .relaxed)
            sharedDefaults?.set(expiry, forKey: SharedKeys.verboseExpiresAt)
        } else {
            verboseExpiresAtBits.store(Double(0).bitPattern, ordering: .relaxed)
            sharedDefaults?.removeObject(forKey: SharedKeys.verboseExpiresAt)
        }
    }

    func refreshVerboseFromDefaults() {
        let stored = sharedDefaults?.double(forKey: SharedKeys.verboseExpiresAt) ?? 0
        verboseExpiresAtBits.store(stored.bitPattern, ordering: .relaxed)
    }

    var lastUploadedAt: Date? {
        get {
            let timestamp = standardDefaults.double(forKey: StandardKeys.lastUploadedAt)
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        set {
            if let newValue {
                standardDefaults.set(newValue.timeIntervalSince1970, forKey: StandardKeys.lastUploadedAt)
            } else {
                standardDefaults.removeObject(forKey: StandardKeys.lastUploadedAt)
            }
        }
    }

    var lastUploadError: String? {
        get { standardDefaults.string(forKey: StandardKeys.lastUploadError) }
        set {
            if let newValue {
                standardDefaults.set(newValue, forKey: StandardKeys.lastUploadError)
            } else {
                standardDefaults.removeObject(forKey: StandardKeys.lastUploadError)
            }
        }
    }

    private func clearExpiredVerbose(expectedBits: UInt64) {
        let (exchanged, _) = verboseExpiresAtBits.compareExchange(
            expected: expectedBits,
            desired: Double(0).bitPattern,
            ordering: .relaxed
        )
        if exchanged {
            sharedDefaults?.removeObject(forKey: SharedKeys.verboseExpiresAt)
        }
    }
}

/// Builds envelope-complete `TelemetryRecord` values with monotonic sequence numbers.
nonisolated final class TelemetryRecordBuilder: Sendable {
    let sessionID: String
    let process: TelemetryProcess
    let environment: TelemetryEnvironment
    let deviceContext: TelemetryDeviceContext
    let settings: TelemetrySettingsStore
    private let sequence = Atomic<Int>(0)

    init(
        sessionID: String = UUID().uuidString.lowercased(),
        process: TelemetryProcess = TelemetryRuntime.currentProcess,
        environment: TelemetryEnvironment = TelemetryRuntime.defaultEnvironment,
        deviceContext: TelemetryDeviceContext = .current(),
        settings: TelemetrySettingsStore
    ) {
        self.sessionID = sessionID
        self.process = process
        self.environment = environment
        self.deviceContext = deviceContext
        self.settings = settings
    }

    func makeRecord(from entry: TelemetryEntry, now: Date = .now) -> TelemetryRecord {
        let (_, seq) = sequence.wrappingAdd(1, ordering: .relaxed)
        let deviceID: String? =
            switch process {
            case .app: settings.ensureDeviceID()
            case .widget: settings.existingDeviceID()
            }
        return TelemetryRecord(
            time: now.formatted(TelemetryRecord.timestampFormat),
            id: UUID().uuidString.lowercased(),
            seq: seq,
            kind: entry.kind,
            level: entry.level,
            category: entry.category,
            name: entry.name,
            message: entry.message,
            sessionID: sessionID,
            deviceID: deviceID,
            process: process,
            env: environment,
            appVersion: deviceContext.appVersion,
            buildNumber: deviceContext.buildNumber,
            osVersion: deviceContext.osVersion,
            deviceModel: deviceContext.deviceModel,
            errorType: entry.errorType,
            errorDomain: entry.errorDomain,
            errorCode: entry.errorCode,
            errorMessage: entry.errorMessage,
            durationMS: entry.durationMS,
            count: entry.count,
            recordID: entry.recordID,
            status: entry.status,
            source: entry.source,
            route: entry.route,
            action: entry.action,
            sql: entry.sql.map { TelemetryRecord.truncateSQL($0) },
            details: entry.details
        )
    }
}

/// Mirrors telemetry records to unified OSLog with `.public` formatting for sysdiagnose and Console.
nonisolated enum TelemetryOSLogMirror {
    private static let startupLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "startup")
    private static let databaseLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "database")
    private static let backupLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "backup")
    private static let calendarLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "calendar")
    private static let scheduleLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "schedule")
    private static let appointmentLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "appointment")
    private static let unavailableTimeLogger = Logger(
        subsystem: TelemetryRuntime.osLogSubsystem, category: "unavailable_time")
    private static let patientLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "patient")
    private static let paymentLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "payment")
    private static let navigationLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "navigation")
    private static let intentLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "intent")
    private static let widgetLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "widget")
    private static let telemetryLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "telemetry")
    private static let metrickitLogger = Logger(subsystem: TelemetryRuntime.osLogSubsystem, category: "metrickit")

    static func mirror(_ record: TelemetryRecord) {
        let logger = logger(for: record.category)
        let line = formattedLine(for: record)
        switch record.level {
        case .debug:
            logger.debug("\(line, privacy: .public)")
        case .info:
            logger.info("\(line, privacy: .public)")
        case .warning:
            logger.warning("\(line, privacy: .public)")
        case .error:
            logger.error("\(line, privacy: .public)")
        case .fault:
            logger.fault("\(line, privacy: .public)")
        }
    }

    private static func logger(for category: TelemetryCategory) -> Logger {
        switch category {
        case .startup: startupLogger
        case .database: databaseLogger
        case .backup: backupLogger
        case .calendar: calendarLogger
        case .schedule: scheduleLogger
        case .appointment: appointmentLogger
        case .unavailableTime: unavailableTimeLogger
        case .patient: patientLogger
        case .payment: paymentLogger
        case .navigation: navigationLogger
        case .intent: intentLogger
        case .widget: widgetLogger
        case .telemetry: telemetryLogger
        case .metrickit: metrickitLogger
        }
    }

    private static func formattedLine(for record: TelemetryRecord) -> String {
        var parts = ["[\(record.kind.rawValue)]", record.name]
        if let action = record.action { parts.append("action=\(action)") }
        if let status = record.status { parts.append("status=\(status)") }
        if let route = record.route { parts.append("route=\(route)") }
        if let source = record.source { parts.append("source=\(source)") }
        if let recordID = record.recordID { parts.append("record_id=\(recordID)") }
        if let durationMS = record.durationMS { parts.append("duration_ms=\(durationMS)") }
        if let count = record.count { parts.append("count=\(count)") }
        if let errorType = record.errorType { parts.append("error=\(errorType)") }
        if let errorMessage = record.errorMessage { parts.append("err_msg=\(errorMessage)") }
        if let message = record.message { parts.append("msg=\(message)") }
        if let sql = record.sql { parts.append("sql=\(sql)") }
        return parts.joined(separator: " ")
    }
}

/// Metadata parsed from a sealed telemetry segment filename.
nonisolated struct TelemetrySegmentInfo: Equatable, Sendable {
    let url: URL
    let filename: String
    let timestampMillis: Int64
    let isDebug: Bool
    let byteSize: Int
}

/// File-backed NDJSON spool shared between the main app and widget extension inside the App Group.
/// Only the main app appends to `active-app.ndjson`, seals, evicts, and deletes files.
/// The widget extension writes immutable sealed segments atomically in one call.
nonisolated final class TelemetrySpool: Sendable {
    static let defaultMaxActiveSegmentBytes = 256 * 1024
    static let defaultMaxTotalBytes = 20 * 1024 * 1024
    static let activeFilename = "active-app.ndjson"

    let directory: URL
    let maxActiveSegmentBytes: Int
    let maxTotalBytes: Int
    let mirrorsToOSLog: Bool

    private struct State {
        var fileHandle: FileHandle?
        var onWrite: (@Sendable (TelemetryLevel) -> Void)?
    }

    private let state = Mutex(State())

    init(
        directory: URL,
        maxActiveSegmentBytes: Int = defaultMaxActiveSegmentBytes,
        maxTotalBytes: Int = defaultMaxTotalBytes,
        mirrorsToOSLog: Bool = true
    ) {
        self.directory = directory
        self.maxActiveSegmentBytes = maxActiveSegmentBytes
        self.maxTotalBytes = maxTotalBytes
        self.mirrorsToOSLog = mirrorsToOSLog
    }

    deinit {
        state.withLock { state in
            try? state.fileHandle?.close()
            state.fileHandle = nil
        }
    }

    static func defaultDirectory(
        environment: TelemetryEnvironment = TelemetryRuntime.defaultEnvironment,
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ClinicalSharedDatabase.appGroupIdentifier
        )?
        .appending(path: "Telemetry", directoryHint: .isDirectory)
        .appending(path: environment.rawValue, directoryHint: .isDirectory)
    }

    var activeFileURL: URL {
        directory.appending(path: Self.activeFilename)
    }

    func setOnWrite(_ handler: (@Sendable (TelemetryLevel) -> Void)?) {
        state.withLock { $0.onWrite = handler }
    }

    /// Appends one record to the main app's active NDJSON file and rotates when the segment limit is reached.
    func append(_ record: TelemetryRecord, now: Date = .now) {
        if mirrorsToOSLog {
            TelemetryOSLogMirror.mirror(record)
        }
        guard var lineData = try? JSONEncoder().encode(record) else { return }
        lineData.append(0x0A)

        let callback: (@Sendable (TelemetryLevel) -> Void)? = state.withLock { state in
            do {
                try ensureDirectory()
                let handle = try openActiveHandle(&state, now: now)
                try handle.seekToEnd()
                // Always use throwing write(contentsOf:) so a full disk cannot raise an ObjC exception.
                try handle.write(contentsOf: lineData)
                let currentSize = try handle.offset()
                if currentSize >= UInt64(maxActiveSegmentBytes) {
                    _ = sealActiveLocked(&state, now: now)
                }
            } catch {
                try? state.fileHandle?.close()
                state.fileHandle = nil
            }
            return state.onWrite
        }
        callback?(record.level)
    }

    /// Writes one immutable widget segment atomically without touching `active-app.ndjson`.
    func writeWidgetSegment(_ records: [TelemetryRecord], now: Date = .now) {
        guard !records.isEmpty else { return }
        if mirrorsToOSLog {
            for record in records {
                TelemetryOSLogMirror.mirror(record)
            }
        }
        let encoder = JSONEncoder()
        var payload = Data()
        for record in records {
            if let encoded = try? encoder.encode(record) {
                payload.append(encoded)
                payload.append(0x0A)
            }
        }
        guard !payload.isEmpty else { return }
        do {
            try ensureDirectory()
            let url = directory.appending(
                path: Self.makeSegmentFilename(
                    timestampMillis: Self.unixMillis(now),
                    process: .widget,
                    isDebug: false
                ))
            try payload.write(to: url, options: [.atomic])
        } catch {
            // Telemetry failures must never interrupt widget rendering.
        }
    }

    /// Seals `active-app.ndjson` into an immutable validated segment and enforces the spool byte cap.
    @discardableResult
    func sealActiveSegment(now: Date = .now) -> URL? {
        state.withLock { state in
            sealActiveLocked(&state, now: now)
        }
    }

    /// Lists all sealed segments sorted strictly by filename timestamp (oldest first).
    func listSealedSegments() -> [TelemetrySegmentInfo] {
        let manager = FileManager.default
        guard
            let names = try? manager.contentsOfDirectory(
                atPath: directory.path(percentEncoded: false))
        else { return [] }

        var segments: [TelemetrySegmentInfo] = []
        for name in names {
            guard let parsed = Self.parseSegmentFilename(name) else { continue }
            let url = directory.appending(path: name)
            let size = Self.fileSize(at: url)
            segments.append(
                TelemetrySegmentInfo(
                    url: url,
                    filename: name,
                    timestampMillis: parsed.timestampMillis,
                    isDebug: parsed.isDebug,
                    byteSize: size
                ))
        }
        return segments.sorted { lhs, rhs in
            if lhs.timestampMillis != rhs.timestampMillis {
                return lhs.timestampMillis < rhs.timestampMillis
            }
            return lhs.filename < rhs.filename
        }
    }

    /// Returns the number of sealed segments plus one if the active file has pending bytes.
    func pendingSegmentCount() -> Int {
        state.withLock { _ in
            let sealed = listSealedSegments().count
            let hasActive = Self.fileSize(at: activeFileURL) > 0
            return sealed + (hasActive ? 1 : 0)
        }
    }

    /// Reads and validates JSON object lines from a sealed segment.
    func readValidatedLines(at url: URL) -> [Data] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        return Self.extractValidatedLines(from: data, requireTrailingNewline: false).lines
    }

    /// Splits an oversized segment in half on HTTP 413, or drops it when only one record remains.
    func splitSegment(at url: URL, now: Date = .now) -> [URL] {
        state.withLock { _ in
            let lines = readValidatedLines(at: url)
            guard lines.count > 1 else {
                try? FileManager.default.removeItem(at: url)
                return []
            }
            let midpoint = lines.count / 2
            let parsed = Self.parseSegmentFilename(url.lastPathComponent)
            let baseMillis = parsed?.timestampMillis ?? Self.unixMillis(now)
            let isDebug = parsed?.isDebug ?? false
            let process: TelemetryProcess =
                url.lastPathComponent.contains("-widget-") ? .widget : .app

            let halves = [Array(lines[..<midpoint]), Array(lines[midpoint...])]
            var created: [URL] = []
            do {
                try ensureDirectory()
                for (offset, half) in halves.enumerated() {
                    var data = Data()
                    for line in half {
                        data.append(line)
                        data.append(0x0A)
                    }
                    let target = directory.appending(
                        path: Self.makeSegmentFilename(
                            timestampMillis: baseMillis + Int64(offset),
                            process: process,
                            isDebug: isDebug
                        ))
                    try data.write(to: target, options: [.atomic])
                    created.append(target)
                }
                try? FileManager.default.removeItem(at: url)
            } catch {
                for target in created {
                    try? FileManager.default.removeItem(at: target)
                }
                return []
            }
            enforceCapLocked()
            return created
        }
    }

    func removeSegment(at url: URL) {
        state.withLock { _ in
            try? FileManager.default.removeItem(at: url)
        }
    }

    func enforceCap() {
        state.withLock { _ in
            enforceCapLocked()
        }
    }

    /// Synchronously seals pending records and writes all segments into one NDJSON export file.
    func exportNDJSON(to destinationURL: URL, now: Date = .now) throws -> Int {
        try state.withLock { state in
            _ = sealActiveLocked(&state, now: now)
            let segments = listSealedSegments()
            let manager = FileManager.default
            if manager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
                try manager.removeItem(at: destinationURL)
            }
            manager.createFile(atPath: destinationURL.path(percentEncoded: false), contents: nil)
            let handle = try FileHandle(forWritingTo: destinationURL)
            defer { try? handle.close() }
            var lineCount = 0
            for segment in segments {
                let lines = readValidatedLines(at: segment.url)
                for line in lines {
                    try handle.write(contentsOf: line)
                    try handle.write(contentsOf: Data([0x0A]))
                    lineCount += 1
                }
            }
            return lineCount
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private func openActiveHandle(_ state: inout State, now: Date) throws -> FileHandle {
        let path = activeFileURL.path(percentEncoded: false)
        if let handle = state.fileHandle, FileManager.default.fileExists(atPath: path) {
            return handle
        }
        try? state.fileHandle?.close()
        state.fileHandle = nil
        if FileManager.default.fileExists(atPath: path) {
            // Seal the prior active file before appending so a crash-torn trailing line
            // cannot join with the next record and drop it on seal.
            _ = sealActiveLocked(&state, now: now)
            if FileManager.default.fileExists(atPath: path) {
                trimTornTrailingLineLocked()
            }
        }
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = activeFileURL
            try? url.setResourceValues(values)
        }
        let handle = try FileHandle(forWritingTo: activeFileURL)
        state.fileHandle = handle
        return handle
    }

    private func trimTornTrailingLineLocked() {
        guard let data = try? Data(contentsOf: activeFileURL), !data.isEmpty, data.last != 0x0A else {
            return
        }
        let validPrefixLength = data.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0
        guard let handle = try? FileHandle(forUpdating: activeFileURL) else { return }
        defer { try? handle.close() }
        try? handle.truncate(atOffset: UInt64(validPrefixLength))
    }

    private func sealActiveLocked(_ state: inout State, now: Date) -> URL? {
        try? state.fileHandle?.close()
        state.fileHandle = nil

        let manager = FileManager.default
        let activePath = activeFileURL.path(percentEncoded: false)
        guard manager.fileExists(atPath: activePath) else {
            enforceCapLocked()
            return nil
        }

        let rawData = (try? Data(contentsOf: activeFileURL)) ?? Data()
        guard !rawData.isEmpty else {
            try? manager.removeItem(at: activeFileURL)
            enforceCapLocked()
            return nil
        }

        // Drop any torn trailing line without `\n` and keep only valid JSON objects.
        let extracted = Self.extractValidatedLines(from: rawData, requireTrailingNewline: true)
        guard !extracted.lines.isEmpty else {
            try? manager.removeItem(at: activeFileURL)
            enforceCapLocked()
            return nil
        }

        var validatedPayload = Data()
        for line in extracted.lines {
            validatedPayload.append(line)
            validatedPayload.append(0x0A)
        }

        let isDebugOnly = extracted.hasDebug && !extracted.hasElevated
        let sealedURL = directory.appending(
            path: Self.makeSegmentFilename(
                timestampMillis: Self.unixMillis(now),
                process: .app,
                isDebug: isDebugOnly
            ))
        do {
            try validatedPayload.write(to: sealedURL, options: [.atomic])
            try? manager.removeItem(at: activeFileURL)
            enforceCapLocked()
            return sealedURL
        } catch {
            return nil
        }
    }

    private func enforceCapLocked() {
        var segments = listSealedSegments()
        var totalBytes =
            segments.reduce(0) { $0 + $1.byteSize } + Self.fileSize(at: activeFileURL)
        guard totalBytes > maxTotalBytes else { return }

        // Evict verbose debug-only segments first (oldest timestamp first), then normal segments.
        while totalBytes > maxTotalBytes, !segments.isEmpty {
            let candidateIndex =
                segments.firstIndex(where: { $0.isDebug }) ?? 0
            let removed = segments.remove(at: candidateIndex)
            try? FileManager.default.removeItem(at: removed.url)
            totalBytes -= removed.byteSize
        }
    }

    private struct ExtractedLines {
        let lines: [Data]
        let hasDebug: Bool
        let hasElevated: Bool
    }

    private static func extractValidatedLines(
        from data: Data,
        requireTrailingNewline: Bool
    ) -> ExtractedLines {
        var rawSlices = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        if requireTrailingNewline {
            if data.last != 0x0A {
                // Drop a partial trailing line left by a mid-write crash.
                if !rawSlices.isEmpty {
                    rawSlices.removeLast()
                }
            }
        }

        var validLines: [Data] = []
        var hasDebug = false
        var hasElevated = false

        for slice in rawSlices where !slice.isEmpty {
            let lineData = Data(slice)
            guard
                let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            if let level = object["level"] as? String {
                if level == TelemetryLevel.debug.rawValue {
                    hasDebug = true
                } else if level == TelemetryLevel.warning.rawValue
                    || level == TelemetryLevel.error.rawValue
                    || level == TelemetryLevel.fault.rawValue
                {
                    hasElevated = true
                }
            }
            validLines.append(lineData)
        }
        return ExtractedLines(lines: validLines, hasDebug: hasDebug, hasElevated: hasElevated)
    }

    static func unixMillis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.towardZero))
    }

    static func makeSegmentFilename(
        timestampMillis: Int64,
        process: TelemetryProcess,
        isDebug: Bool,
        uuid: UUID = UUID()
    ) -> String {
        let clamped = max(0, timestampMillis)
        let raw = String(clamped)
        let padded = raw.count < 13 ? String(repeating: "0", count: 13 - raw.count) + raw : raw
        let tag = isDebug ? "\(process.rawValue)-debug" : process.rawValue
        return "seg-\(padded)-\(tag)-\(uuid.uuidString.lowercased()).ndjson"
    }

    static func parseSegmentFilename(_ filename: String) -> (timestampMillis: Int64, isDebug: Bool)? {
        guard filename.hasPrefix("seg-"), filename.hasSuffix(".ndjson") else { return nil }
        let stem = filename.dropFirst(4).dropLast(7)
        let parts = stem.split(separator: "-")
        guard parts.count >= 3, let millis = Int64(parts[0]) else { return nil }
        let isDebug = parts.count >= 4 && parts[2] == "debug"
        return (millis, isDebug)
    }

    private static func fileSize(at url: URL) -> Int {
        guard
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: url.path(percentEncoded: false)),
            let size = attributes[.size] as? NSNumber
        else { return 0 }
        return size.intValue
    }
}
