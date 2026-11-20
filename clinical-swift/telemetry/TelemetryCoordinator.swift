import ClinicalModels
import CoreTransferable
import Dependencies
import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

/// Synchronous NDJSON log export document for SwiftUI `ShareLink`.
nonisolated struct TelemetryExportDocument: Transferable, Sendable {
    let spool: TelemetrySpool

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { document in
            let filename = "clinical-logs-\(Int(Date.now.timeIntervalSince1970)).ndjson"
            let url = FileManager.default.temporaryDirectory.appending(path: filename)
            _ = try document.spool.exportNDJSON(to: url)
            return SentTransferredFile(url, allowAccessingOriginalFile: false)
        }
    }
}

/// Manages telemetry spool sealing, debounced and lifecycle flushes, Axiom HTTP delivery,
/// verbose mode auto-expiry, and Diagnostics settings state.
@MainActor @Observable
final class TelemetryCoordinator {
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.continuousClock) private var clock
    @ObservationIgnored @Dependency(\.telemetry) private var telemetry
    @ObservationIgnored @Dependency(\.telemetryBackgroundTaskScheduler) private var backgroundTaskScheduler

    private(set) var isUploading = false
    private(set) var pendingSegmentCount = 0
    private(set) var lastUploadedAt: Date?
    private(set) var lastUploadError: String?
    private(set) var isAuthHalted = false
    private(set) var verboseExpiresAt: Date?
    private(set) var backoffUntil: Date?

    private let spool: TelemetrySpool
    private let settings: TelemetrySettingsStore
    private let configuration: TelemetryConfiguration
    private let encoder: any LogBatchEncoder
    private let session: URLSession
    private let normalFlushDelay: Duration
    private let errorFlushDelay: Duration

    private var activeFlushTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var debounceIsUrgent = false
    private var retryTask: Task<Void, Never>?
    private var retryDeadline: Date?
    private var isForeground = true
    private var consecutiveFailures = 0

    init(
        spool: TelemetrySpool,
        settings: TelemetrySettingsStore,
        configuration: TelemetryConfiguration,
        encoder: any LogBatchEncoder = AxiomFlatJSONEncoder(),
        session: URLSession = .shared,
        normalFlushDelay: Duration = .seconds(60),
        errorFlushDelay: Duration = .seconds(5),
        attachWriteHook: Bool = true
    ) {
        self.spool = spool
        self.settings = settings
        self.configuration = configuration
        self.encoder = encoder
        self.session = session
        self.normalFlushDelay = normalFlushDelay
        self.errorFlushDelay = errorFlushDelay
        self.lastUploadedAt = settings.lastUploadedAt
        self.lastUploadError = settings.lastUploadError
        refreshState()

        if attachWriteHook {
            spool.setOnWrite { [weak self] level in
                Task { @MainActor [weak self] in
                    self?.noteRecordWritten(level: level)
                }
            }
        }
    }

    static func live() -> TelemetryCoordinator {
        let runtime = TelemetryLiveRuntime.shared
        return TelemetryCoordinator(
            spool: runtime.spool,
            settings: runtime.settings,
            configuration: TelemetryConfiguration.live()
        )
    }

    static func disabled() -> TelemetryCoordinator {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "telemetry-disabled-\(UUID().uuidString)", directoryHint: .isDirectory)
        let settings = TelemetrySettingsStore(sharedDefaults: nil)
        let config = TelemetryConfiguration(
            ingestURL: nil,
            dataset: "",
            ingestToken: "",
            environment: .dev,
            isUploadEnabled: false
        )
        return TelemetryCoordinator(
            spool: TelemetrySpool(directory: tempDir, mirrorsToOSLog: false),
            settings: settings,
            configuration: config,
            attachWriteHook: false
        )
    }

    var isUploadConfigured: Bool {
        configuration.isUploadEnabled
    }

    var isVerboseEnabled: Bool {
        guard let expiresAt = verboseExpiresAt else { return false }
        return expiresAt > now
    }

    var statusText: String {
        if isUploading { return "Uploading..." }
        if !configuration.isUploadEnabled {
            return pendingSegmentCount > 0 ? "\(pendingSegmentCount) pending (local only)" : "Local only"
        }
        if pendingSegmentCount > 0 {
            return "\(pendingSegmentCount) pending"
        }
        return "Up to date"
    }

    var exportDocument: TelemetryExportDocument {
        TelemetryExportDocument(spool: spool)
    }

    func refreshState() {
        verboseExpiresAt = settings.verboseExpiresAt(at: now)
        pendingSegmentCount = spool.pendingSegmentCount()
        lastUploadedAt = settings.lastUploadedAt
        lastUploadError = settings.lastUploadError
    }

    func setVerboseEnabled(_ enabled: Bool) {
        settings.setVerboseEnabled(enabled, now: now)
        verboseExpiresAt = settings.verboseExpiresAt(at: now)
        telemetry.event(
            category: .telemetry,
            name: "verbose_logging_changed",
            status: enabled ? "enabled" : "disabled"
        )
        pendingSegmentCount = spool.pendingSegmentCount()
    }

    /// Unified debounced flush trigger: ~5s for errors/faults, ~60s for normal writes.
    func noteRecordWritten(level: TelemetryLevel) {
        pendingSegmentCount = max(pendingSegmentCount, 1)
        guard configuration.isUploadEnabled, !isAuthHalted else { return }

        let urgent = level == .error || level == .fault
        if debounceTask != nil {
            if urgent && !debounceIsUrgent {
                debounceTask?.cancel()
            } else {
                return
            }
        }

        debounceIsUrgent = urgent
        let delay = urgent ? errorFlushDelay : normalFlushDelay
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await self?.clock.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.debounceTask = nil
            self.debounceIsUrgent = false
            await self.flush(manual: false)
        }
    }

    func handleForeground() {
        isForeground = true
        refreshState()
        cancelScheduledTasks()
        Task { @MainActor [weak self] in
            await self?.flush(manual: false)
        }
    }

    func handleBackground() {
        isForeground = false
        cancelScheduledTasks()

        guard configuration.isUploadEnabled, !isAuthHalted else {
            let spool = self.spool
            let timestamp = now
            Task {
                _ = await Self.sealAndList(spool: spool, now: timestamp)
            }
            return
        }

        let scheduler = backgroundTaskScheduler
        let handle = BackgroundFlushHandle(
            endTask: scheduler.end,
            onExpire: { [weak self] in
                self?.activeFlushTask?.cancel()
            }
        )
        let taskID = scheduler.begin("in.bitehaus.clinical.telemetry.flush") {
            Task { @MainActor in
                handle.expire()
            }
        }
        handle.taskID = taskID
        handle.uploadTask = Task { @MainActor [weak self] in
            defer { handle.finish() }
            await self?.flush(manual: false)
        }
    }

    func sendNow() async {
        cancelScheduledTasks()
        isAuthHalted = false
        backoffUntil = nil
        consecutiveFailures = 0
        await flush(manual: true)
    }

    func flush(manual: Bool) async {
        if let activeFlushTask {
            if Task.isCancelled {
                activeFlushTask.cancel()
                return
            }
            await withTaskCancellationHandler {
                await activeFlushTask.value
            } onCancel: {
                activeFlushTask.cancel()
            }
            return
        }
        guard !Task.isCancelled else { return }
        let task = Task { @MainActor in
            await self.performFlush(manual: manual)
        }
        activeFlushTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        activeFlushTask = nil
    }

    private func performFlush(manual: Bool) async {
        verboseExpiresAt = settings.verboseExpiresAt(at: now)
        guard configuration.isUploadEnabled, let ingestURL = configuration.ingestURL else {
            pendingSegmentCount = await Self.countPendingSegments(spool: spool)
            return
        }
        if !manual {
            guard !isAuthHalted else { return }
            if let backoffUntil, now < backoffUntil {
                scheduleRetryIfNeeded(until: backoffUntil)
                return
            }
        }

        isUploading = true
        defer {
            isUploading = false
        }

        let segments = await Self.sealAndList(spool: spool, now: now)
        var queue = segments.map(\.url)
        pendingSegmentCount = queue.count

        while !queue.isEmpty {
            guard !Task.isCancelled else { break }
            let segmentURL = queue.removeFirst()

            let compressedPayload: Data?
            do {
                compressedPayload = try await Self.prepareUpload(
                    segmentURL: segmentURL,
                    spool: spool,
                    encoder: encoder
                )
            } catch {
                recordUploadError("Failed to prepare telemetry batch: \(error.localizedDescription)")
                await Self.removeSegment(at: segmentURL, spool: spool)
                pendingSegmentCount = queue.count
                continue
            }

            guard let body = compressedPayload else {
                await Self.removeSegment(at: segmentURL, spool: spool)
                pendingSegmentCount = queue.count
                continue
            }
            guard !Task.isCancelled else { break }

            var request = URLRequest(url: ingestURL)
            request.httpMethod = "POST"
            request.httpBody = body
            request.timeoutInterval = 30
            request.setValue("Bearer \(configuration.ingestToken)", forHTTPHeaderField: "Authorization")
            request.setValue(encoder.contentType, forHTTPHeaderField: "Content-Type")
            request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    applyBackoff(message: "Telemetry upload received an invalid server response.")
                    break
                }

                switch http.statusCode {
                case 200..<300:
                    handleSuccess(data: data)
                    await Self.removeSegment(at: segmentURL, spool: spool)
                    pendingSegmentCount = queue.count

                case 401, 403:
                    isAuthHalted = true
                    cancelRetryTask()
                    recordUploadError(
                        "Telemetry upload unauthorized (HTTP \(http.statusCode)). Check the Axiom ingest token."
                    )
                    queue.removeAll()

                case 429, 503:
                    let delay =
                        Self.parseRetryAfter(
                            http.value(forHTTPHeaderField: "Retry-After"), now: now)
                        ?? nextExponentialBackoff()
                    let deadline = now.addingTimeInterval(delay)
                    backoffUntil = deadline
                    scheduleRetryIfNeeded(until: deadline, allowZeroDelay: true)
                    recordUploadError(
                        "Telemetry upload throttled (HTTP \(http.statusCode)). Retrying later."
                    )
                    queue.removeAll()

                case 413:
                    let splitURLs = await Self.splitOversizedSegment(
                        at: segmentURL, spool: spool, now: now)
                    if splitURLs.isEmpty {
                        recordUploadError("Dropped an oversized telemetry record (HTTP 413).")
                    } else {
                        queue.insert(contentsOf: splitURLs, at: 0)
                    }
                    pendingSegmentCount = queue.count

                case 400..<500:
                    await Self.removeSegment(at: segmentURL, spool: spool)
                    recordUploadError("Dropped a rejected telemetry batch (HTTP \(http.statusCode)).")
                    pendingSegmentCount = queue.count

                default:
                    applyBackoff(
                        message: "Telemetry server error (HTTP \(http.statusCode)). Retrying later."
                    )
                    queue.removeAll()
                }
            } catch is CancellationError {
                break
            } catch let error as URLError where error.code == .cancelled {
                break
            } catch {
                if Task.isCancelled { break }
                applyBackoff(
                    message: "Telemetry upload failed: \(error.localizedDescription)"
                )
                break
            }
        }

        pendingSegmentCount = await Self.countPendingSegments(spool: spool)
    }

    private func handleSuccess(data: Data) {
        consecutiveFailures = 0
        backoffUntil = nil
        cancelRetryTask()
        let uploadedAt = now
        lastUploadedAt = uploadedAt
        settings.lastUploadedAt = uploadedAt

        if let summary = try? JSONDecoder().decode(AxiomIngestResponse.self, from: data),
            let failed = summary.failed, failed > 0
        {
            let detail = summary.failures?.first?.error
            let message =
                detail.map { "Axiom rejected \(failed) record(s): \($0)" }
                ?? "Axiom rejected \(failed) record(s)."
            recordUploadError(message)
        } else {
            lastUploadError = nil
            settings.lastUploadError = nil
        }
    }

    private func applyBackoff(message: String) {
        let delay = nextExponentialBackoff()
        let deadline = now.addingTimeInterval(delay)
        backoffUntil = deadline
        scheduleRetryIfNeeded(until: deadline)
        recordUploadError(message)
    }

    private func cancelScheduledTasks() {
        debounceTask?.cancel()
        debounceTask = nil
        debounceIsUrgent = false
        cancelRetryTask()
    }

    private func cancelRetryTask() {
        retryTask?.cancel()
        retryTask = nil
        retryDeadline = nil
    }

    private func scheduleRetryIfNeeded(until deadline: Date, allowZeroDelay: Bool = false) {
        guard isForeground, configuration.isUploadEnabled, !isAuthHalted else { return }
        let remaining = deadline.timeIntervalSince(now)
        if allowZeroDelay {
            guard remaining >= 0 else { return }
        } else {
            guard remaining > 0 else { return }
        }
        if retryDeadline == deadline, retryTask != nil {
            return
        }
        cancelRetryTask()
        retryDeadline = deadline
        let delay = Duration.seconds(max(0, remaining))
        retryTask = Task { @MainActor [weak self] in
            do {
                try await self?.clock.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            self.retryDeadline = nil
            await self.flush(manual: false)
        }
    }

    private func nextExponentialBackoff() -> TimeInterval {
        consecutiveFailures = min(consecutiveFailures + 1, 10)
        return min(3600, 30 * pow(2, Double(consecutiveFailures - 1)))
    }

    private func recordUploadError(_ message: String) {
        lastUploadError = message
        settings.lastUploadError = message
    }

    static func parseRetryAfter(_ header: String?, now: Date) -> TimeInterval? {
        guard let header else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return seconds
        }
        let httpDateStrategy = Date.ParseStrategy(
            format:
                "\(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) GMT",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: .gmt
        )
        if let date = try? Date(trimmed, strategy: httpDateStrategy) {
            return max(0, date.timeIntervalSince(now))
        }
        return nil
    }

    @concurrent
    private static func sealAndList(
        spool: TelemetrySpool,
        now: Date
    ) async -> [TelemetrySegmentInfo] {
        _ = spool.sealActiveSegment(now: now)
        return spool.listSealedSegments()
    }

    @concurrent
    private static func prepareUpload(
        segmentURL: URL,
        spool: TelemetrySpool,
        encoder: any LogBatchEncoder
    ) async throws -> Data? {
        let lines = spool.readValidatedLines(at: segmentURL)
        guard !lines.isEmpty else { return nil }
        let encoded = encoder.encode(lines)
        return try GzipCompressor.compress(encoded)
    }

    @concurrent
    private static func splitOversizedSegment(
        at url: URL,
        spool: TelemetrySpool,
        now: Date
    ) async -> [URL] {
        spool.splitSegment(at: url, now: now)
    }

    @concurrent
    private static func removeSegment(at url: URL, spool: TelemetrySpool) async {
        spool.removeSegment(at: url)
    }

    @concurrent
    private static func countPendingSegments(spool: TelemetrySpool) async -> Int {
        spool.pendingSegmentCount()
    }
}

private nonisolated struct AxiomIngestResponse: Decodable, Sendable {
    let ingested: Int?
    let failed: Int?
    let failures: [Failure]?

    struct Failure: Decodable, Sendable {
        let error: String?
    }
}

nonisolated struct TelemetryBackgroundTaskScheduler: DependencyKey, Sendable {
    var begin:
        @MainActor (
            _ name: String,
            _ expirationHandler: @escaping @Sendable () -> Void
        ) -> UIBackgroundTaskIdentifier
    var end: @MainActor (UIBackgroundTaskIdentifier) -> Void

    static let liveValue = Self(
        begin: { name, expirationHandler in
            UIApplication.shared.beginBackgroundTask(
                withName: name,
                expirationHandler: expirationHandler
            )
        },
        end: { taskID in
            UIApplication.shared.endBackgroundTask(taskID)
        }
    )

    static let testValue = liveValue
}

nonisolated extension DependencyValues {
    var telemetryBackgroundTaskScheduler: TelemetryBackgroundTaskScheduler {
        get { self[TelemetryBackgroundTaskScheduler.self] }
        set { self[TelemetryBackgroundTaskScheduler.self] = newValue }
    }
}

@MainActor
private final class BackgroundFlushHandle {
    var taskID: UIBackgroundTaskIdentifier = .invalid
    var uploadTask: Task<Void, Never>?
    private let endTask: @MainActor (UIBackgroundTaskIdentifier) -> Void
    private let onExpire: @MainActor () -> Void

    init(
        endTask: @escaping @MainActor (UIBackgroundTaskIdentifier) -> Void,
        onExpire: @escaping @MainActor () -> Void
    ) {
        self.endTask = endTask
        self.onExpire = onExpire
    }

    func expire() {
        uploadTask?.cancel()
        onExpire()
        finish()
    }

    func finish() {
        guard taskID != .invalid else { return }
        let id = taskID
        taskID = .invalid
        endTask(id)
    }
}
