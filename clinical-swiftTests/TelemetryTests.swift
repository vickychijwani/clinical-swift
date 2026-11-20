import ClinicalModels
import Dependencies
import Foundation
import Synchronization
import Testing
import UIKit

@testable import clinical_swift

@MainActor
struct TelemetryTests {
    @Test func recordSchemaStaysBelowFortyFixedKeysAndTruncatesSQL() throws {
        #expect(TelemetryRecord.CodingKeys.allCases.count < 40)
        #expect(TelemetryLevel.allCases.map(\.rawValue) == ["debug", "info", "warning", "error", "fault"])

        let longSQL = String(repeating: "SELECT patient FROM appointments; ", count: 200)
        let truncated = TelemetryRecord.truncateSQL(longSQL)
        #expect(truncated.utf8.count <= TelemetryRecord.maxSQLBytes)
        #expect(truncated.hasSuffix("…[truncated]"))

        let shortSQL = "SELECT 1"
        #expect(TelemetryRecord.truncateSQL(shortSQL) == shortSQL)

        let record = makeRecord(
            seq: 1,
            level: .info,
            name: "schema_check",
            sql: truncated
        )
        let data = try JSONEncoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["_time"] as? String == record.time)
        #expect(object.keys.count < 40)
        let decoded = try JSONDecoder().decode(TelemetryRecord.self, from: data)
        #expect(decoded == record)
    }

    @Test func configurationResolvesLegacyAndRegionalURLsAndDisablesOutsideLive() {
        let legacy = TelemetryConfiguration.resolve(
            infoDictionary: [
                "AxiomIngestURL": "https://api.axiom.co/v1/datasets/clinical-dev/ingest",
                "AxiomIngestDataset": "clinical-dev",
                "AxiomIngestToken": "xaat-test-token",
            ],
            context: .live,
            arguments: []
        )
        #expect(legacy.isUploadEnabled)
        #expect(legacy.environment == .dev)
        #expect(legacy.ingestURL?.absoluteString == "https://api.axiom.co/v1/datasets/clinical-dev/ingest")

        let regional = TelemetryConfiguration.resolve(
            infoDictionary: [
                "AxiomIngestURL": "https://us-east-1.aws.edge.axiom.co/v1/ingest/clinical-prod",
                "AxiomIngestDataset": "clinical-prod",
                "AxiomIngestToken": "xaat-prod-token",
            ],
            context: .live,
            arguments: []
        )
        #expect(regional.isUploadEnabled)
        #expect(regional.environment == .prod)
        #expect(
            regional.ingestURL?.absoluteString
                == "https://us-east-1.aws.edge.axiom.co/v1/ingest/clinical-prod"
        )

        let missingToken = TelemetryConfiguration.resolve(
            infoDictionary: [
                "AxiomIngestURL": "https://api.axiom.co/v1/datasets/clinical-dev/ingest",
                "AxiomIngestDataset": "clinical-dev",
                "AxiomIngestToken": "",
            ],
            context: .live,
            arguments: []
        )
        #expect(!missingToken.isUploadEnabled)

        let testContext = TelemetryConfiguration.resolve(
            infoDictionary: [
                "AxiomIngestURL": "https://api.axiom.co/v1/datasets/clinical-dev/ingest",
                "AxiomIngestDataset": "clinical-dev",
                "AxiomIngestToken": "xaat-test-token",
            ],
            context: .test,
            arguments: []
        )
        #expect(!testContext.isUploadEnabled)

        let uiTesting = TelemetryConfiguration.resolve(
            infoDictionary: [
                "AxiomIngestURL": "https://api.axiom.co/v1/datasets/clinical-dev/ingest",
                "AxiomIngestDataset": "clinical-dev",
                "AxiomIngestToken": "xaat-test-token",
            ],
            context: .live,
            arguments: ["--ui-testing-timeline-adjustment"]
        )
        #expect(!uiTesting.isUploadEnabled)

        // Even with live tokens configured in Bundle.main, hosted unit tests must disable uploads.
        let bundleConfig = TelemetryConfiguration.live()
        #expect(!bundleConfig.isUploadEnabled)
        #expect(bundleConfig.dataset == "clinical-dev")
        #expect(
            bundleConfig.ingestURL?.absoluteString
                == "https://eu-central-1.aws.edge.axiom.co/v1/ingest/clinical-dev"
        )
    }

    @Test func spoolTrimsCrashTruncatedTrailingLineAndExportsValidNDJSON() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let spool = TelemetrySpool(directory: dir, mirrorsToOSLog: false)

        let record1 = makeRecord(seq: 1, level: .info, name: "first_event")
        let record2 = makeRecord(seq: 2, level: .error, name: "second_event")
        spool.append(record1, now: try Date("2026-10-01T10:00:00Z", strategy: .iso8601))
        spool.append(record2, now: try Date("2026-10-01T10:00:01Z", strategy: .iso8601))

        // Simulate a crash leaving a torn trailing JSON line without a trailing newline.
        let handle = try FileHandle(forWritingTo: spool.activeFileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"_time\":\"2026-10-01T10:00:02Z\",\"broken".utf8))
        try handle.close()

        // Simulate relaunch appending a new record before any manual seal runs.
        let relaunchedSpool = TelemetrySpool(directory: dir, mirrorsToOSLog: false)
        let record3 = makeRecord(seq: 3, level: .info, name: "relaunch_event")
        relaunchedSpool.append(record3, now: try Date("2026-10-01T10:00:04Z", strategy: .iso8601))

        let sealed = try #require(
            relaunchedSpool.sealActiveSegment(
                now: try Date("2026-10-01T10:00:05Z", strategy: .iso8601)))
        #expect(relaunchedSpool.readValidatedLines(at: sealed).count == 1)
        let allSealedLines = relaunchedSpool.listSealedSegments().flatMap {
            relaunchedSpool.readValidatedLines(at: $0.url)
        }
        #expect(allSealedLines.count == 3)

        let exportURL = dir.appending(path: "export.ndjson")
        let exportedCount = try relaunchedSpool.exportNDJSON(to: exportURL)
        #expect(exportedCount == 3)
        let exportedText = try String(contentsOf: exportURL, encoding: .utf8)
        let exportedLines = exportedText.split(separator: "\n")
        #expect(exportedLines.count == 3)
        let exportedNames = try Set(
            exportedLines.map {
                try JSONDecoder().decode(TelemetryRecord.self, from: Data($0.utf8)).name
            }
        )
        #expect(exportedNames == ["first_event", "second_event", "relaunch_event"])
    }

    @Test func spoolRotatesAtByteLimitAndEvictsDebugSegmentsFirst() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Use small thresholds to verify rotation and debug-first eviction deterministically.
        let spool = TelemetrySpool(
            directory: dir,
            maxActiveSegmentBytes: 400,
            maxTotalBytes: 1800,
            mirrorsToOSLog: false
        )

        let base = try Date("2026-10-01T10:00:00Z", strategy: .iso8601)
        // Appending a record that exceeds 400 bytes rotates automatically into a sealed segment.
        spool.append(
            makeRecord(
                seq: 1, level: .error, name: "important_error",
                message: String(repeating: "E", count: 220)),
            now: base
        )
        let sealedAfterFirst = spool.listSealedSegments()
        #expect(sealedAfterFirst.count == 1)
        let errorSegment = sealedAfterFirst[0].url
        #expect(!errorSegment.lastPathComponent.contains("-debug-"))

        // Subsequent debug segments rotate and trigger cap enforcement; debug segments must be
        // evicted before errorSegment.
        for index in 2...10 {
            spool.append(
                makeRecord(
                    seq: index, level: .debug, name: "sql_query",
                    sql: String(repeating: "S", count: 220)),
                now: base.addingTimeInterval(Double(index))
            )
        }

        let remaining = spool.listSealedSegments()
        let totalSize = remaining.reduce(0) { $0 + $1.byteSize }
        #expect(totalSize <= 1800)
        #expect(remaining.contains(where: { $0.url == errorSegment }))
        #expect(remaining.contains(where: { $0.isDebug }))
    }

    @Test func spoolIsolatesEnvironmentsAndWritesAtomicWidgetSegmentsWithoutMintingDeviceID() throws
    {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let devSpool = TelemetrySpool(
            directory: root.appending(path: "dev", directoryHint: .isDirectory),
            mirrorsToOSLog: false
        )
        let prodSpool = TelemetrySpool(
            directory: root.appending(path: "prod", directoryHint: .isDirectory),
            mirrorsToOSLog: false
        )

        let suiteName = "in.bitehaus.clinical.telemetry.test.\(UUID().uuidString)"
        let sharedDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { sharedDefaults.removePersistentDomain(forName: suiteName) }
        let settings = TelemetrySettingsStore(sharedDefaults: sharedDefaults)

        // Widget must never mint a device_id before first app launch.
        let widgetBuilder = TelemetryRecordBuilder(
            process: .widget, environment: .dev, settings: settings)
        let widgetRecord = widgetBuilder.makeRecord(
            from: TelemetryEntry(
                kind: .event, level: .info, category: .widget, name: "widget_snapshot_loaded",
                count: 3)
        )
        #expect(widgetRecord.deviceID == nil)
        #expect(widgetRecord.process == .widget)

        devSpool.writeWidgetSegment(
            [widgetRecord],
            now: try Date("2026-10-01T11:00:00Z", strategy: .iso8601)
        )
        #expect(devSpool.listSealedSegments().count == 1)
        #expect(devSpool.listSealedSegments()[0].filename.contains("-widget-"))
        #expect(!FileManager.default.fileExists(atPath: devSpool.activeFileURL.path(percentEncoded: false)))
        #expect(prodSpool.listSealedSegments().isEmpty)

        // Main app mints a stable device_id shared thereafter.
        let appBuilder = TelemetryRecordBuilder(
            process: .app, environment: .dev, settings: settings)
        let appRecord = appBuilder.makeRecord(
            from: TelemetryEntry(kind: .event, level: .info, category: .startup, name: "app_launched")
        )
        let mintedID = try #require(appRecord.deviceID)
        #expect(settings.existingDeviceID() == mintedID)
    }

    @Test func axiomEncoderAndGzipRoundTripProducesValidRFC1952Payload() throws {
        let encoder = AxiomFlatJSONEncoder()
        let line1 = try JSONEncoder().encode(makeRecord(seq: 1, level: .info, name: "event_one"))
        let line2 = try JSONEncoder().encode(makeRecord(seq: 2, level: .warning, name: "event_two"))
        let encoded = encoder.encode([line1, line2])

        let jsonArray = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        #expect(jsonArray.count == 2)

        let compressed = try GzipCompressor.compress(encoded)
        #expect(compressed.count >= 10)
        // RFC 1952 magic header: 0x1f, 0x8b, deflate method 0x08.
        #expect(compressed[0] == 0x1f)
        #expect(compressed[1] == 0x8b)
        #expect(compressed[2] == 0x08)

        let decompressed = try GzipCompressor.decompress(compressed)
        #expect(decompressed == encoded)

        // Also test multi-chunk round-trip (> 32 KB).
        let large = Data(String(repeating: "{\"msg\":\"clinical-telemetry-check\"}\n", count: 1500).utf8)
        let compressedLarge = try GzipCompressor.compress(large)
        #expect(compressedLarge.count < large.count)
        #expect(try GzipCompressor.decompress(compressedLarge) == large)
    }

    @Test func coordinatorHandlesClean200AndPartialFailure200() async throws {
        let now = try Date("2026-10-01T12:00:00Z", strategy: .iso8601)
        let (coordinator, spool, cleanup) = try makeCoordinator(now: now) { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            #expect(request.value(forHTTPHeaderField: "Content-Encoding") == "gzip")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try Self.readHTTPBody(from: request)
            let decompressed = try GzipCompressor.decompress(body)
            let items = try #require(
                JSONSerialization.jsonObject(with: decompressed) as? [[String: Any]])
            #expect(items.count == 1)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"ingested\":1,\"failed\":0}".utf8))
        }
        defer { cleanup() }

        spool.append(makeRecord(seq: 1, level: .info, name: "ok_event"), now: now)
        await withDependencies {
            $0.date.now = now
        } operation: {
            await coordinator.flush(manual: false)
        }

        #expect(coordinator.lastUploadedAt == now)
        #expect(coordinator.lastUploadError == nil)
        #expect(spool.listSealedSegments().isEmpty)

        // Now test 200 with failed > 0: records error AND deletes segment so ingested rows are not duplicated.
        let (partialCoordinator, partialSpool, partialCleanup) = try makeCoordinator(now: now) {
            request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload =
                "{\"ingested\":1,\"failed\":1,\"failures\":[{\"error\":\"field limit reached\"}]}"
            return (response, Data(payload.utf8))
        }
        defer { partialCleanup() }

        partialSpool.append(makeRecord(seq: 1, level: .info, name: "partial_event"), now: now)
        await withDependencies {
            $0.date.now = now
        } operation: {
            await partialCoordinator.flush(manual: false)
        }

        #expect(partialCoordinator.lastUploadedAt == now)
        #expect(partialCoordinator.lastUploadError?.contains("field limit reached") == true)
        #expect(partialSpool.listSealedSegments().isEmpty)
    }

    @Test func coordinatorHaltsOn401And403AndRetriesManually() async throws {
        let now = try Date("2026-10-01T12:00:00Z", strategy: .iso8601)
        let attempts = Mutex(0)
        let (coordinator, spool, cleanup) = try makeCoordinator(now: now) { request in
            let count = attempts.withLock { value -> Int in
                value += 1
                return value
            }
            let status = count == 1 ? 401 : 200
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"ingested\":1,\"failed\":0}".utf8))
        }
        defer { cleanup() }

        spool.append(makeRecord(seq: 1, level: .info, name: "auth_test"), now: now)
        await withDependencies {
            $0.date.now = now
        } operation: {
            await coordinator.flush(manual: false)
            #expect(coordinator.isAuthHalted)
            #expect(coordinator.lastUploadError?.contains("401") == true)
            #expect(spool.listSealedSegments().count == 1)

            // Automatic flush stays halted.
            await coordinator.flush(manual: false)
            #expect(attempts.withLock { $0 } == 1)

            // Manual sendNow clears the halt and uploads the retained segment.
            await coordinator.sendNow()
            #expect(!coordinator.isAuthHalted)
            #expect(coordinator.lastUploadError == nil)
            #expect(spool.listSealedSegments().isEmpty)
        }
    }

    @Test func coordinatorHonors429RetryAfterAnd500ExponentialBackoff() async throws {
        let now = try Date("2026-10-01T12:00:00Z", strategy: .iso8601)
        let (coordinator429, spool429, cleanup429) = try makeCoordinator(now: now) { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "120"]
            )!
            return (response, Data())
        }
        defer { cleanup429() }

        spool429.append(makeRecord(seq: 1, level: .info, name: "rate_limited"), now: now)
        await withDependencies {
            $0.date.now = now
        } operation: {
            await coordinator429.flush(manual: false)
        }
        #expect(coordinator429.backoffUntil == now.addingTimeInterval(120))
        #expect(spool429.listSealedSegments().count == 1)

        // Verify HTTP-date parsing in Retry-After as well.
        let dateDelay = TelemetryCoordinator.parseRetryAfter(
            "Thu, 01 Oct 2026 12:05:00 GMT", now: now)
        #expect(dateDelay == 300)

        // Verify 500 retains segments and applies exponential backoff (30s then 60s).
        let (coordinator500, spool500, cleanup500) = try makeCoordinator(now: now) { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { cleanup500() }

        spool500.append(makeRecord(seq: 1, level: .info, name: "server_err"), now: now)
        await withDependencies {
            $0.date.now = now
        } operation: {
            await coordinator500.flush(manual: false)
        }
        #expect(coordinator500.backoffUntil == now.addingTimeInterval(30))
        #expect(spool500.listSealedSegments().count == 1)

        let afterFirstBackoff = now.addingTimeInterval(31)
        await withDependencies {
            $0.date.now = afterFirstBackoff
        } operation: {
            await coordinator500.flush(manual: false)
        }
        #expect(coordinator500.backoffUntil == afterFirstBackoff.addingTimeInterval(60))
        #expect(spool500.listSealedSegments().count == 1)
    }

    @Test func coordinatorSplitsSegmentOn413AndDropsSingleOversizedRecord() async throws {
        let now = try Date("2026-10-01T12:00:00Z", strategy: .iso8601)
        let receivedCounts = Mutex<[Int]>([])
        let (coordinator, spool, cleanup) = try makeCoordinator(now: now) { request in
            let body = try Self.readHTTPBody(from: request)
            let decompressed = try GzipCompressor.decompress(body)
            let items = try #require(
                JSONSerialization.jsonObject(with: decompressed) as? [[String: Any]])
            receivedCounts.withLock { $0.append(items.count) }
            let status = items.count > 1 ? 413 : 200
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"ingested\":\(items.count),\"failed\":0}".utf8))
        }
        defer { cleanup() }

        spool.append(makeRecord(seq: 1, level: .info, name: "part_1"), now: now)
        spool.append(makeRecord(seq: 2, level: .info, name: "part_2"), now: now)
        await withDependencies {
            $0.date.now = now
        } operation: {
            await coordinator.flush(manual: false)
        }

        #expect(receivedCounts.withLock { $0 } == [2, 1, 1])
        #expect(spool.listSealedSegments().isEmpty)

        // Single record receiving 413 is dropped cleanly.
        let (dropCoordinator, dropSpool, dropCleanup) = try makeCoordinator(now: now) { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 413, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { dropCleanup() }

        dropSpool.append(makeRecord(seq: 1, level: .info, name: "huge_single"), now: now)
        await withDependencies {
            $0.date.now = now
        } operation: {
            await dropCoordinator.flush(manual: false)
        }
        #expect(dropSpool.listSealedSegments().isEmpty)
        #expect(dropCoordinator.lastUploadError?.contains("413") == true)
    }

    @Test func coordinatorCancelsActiveAndWaitingUploadsOnBackgroundExpiry() async throws {
        let now = try Date("2026-10-01T12:00:00Z", strategy: .iso8601)

        // Part 1: Background flush owns the active upload and expires while the request is held open.
        try await verifyBackgroundExpiryCancelsHeldUpload(now: now, startForegroundFirst: false)

        // Part 2: Background flush joins an in-flight foreground upload and expires while waiting.
        try await verifyBackgroundExpiryCancelsHeldUpload(now: now, startForegroundFirst: true)
    }

    private func verifyBackgroundExpiryCancelsHeldUpload(
        now: Date,
        startForegroundFirst: Bool
    ) async throws {
        let state = Mutex<(
            startedCount: Int,
            cancelledCount: Int,
            expirationHandler: (@Sendable () -> Void)?,
            endedTaskIDs: [UIBackgroundTaskIdentifier],
            startedContinuation: CheckedContinuation<Void, Never>?,
            cancelledContinuation: CheckedContinuation<Void, Never>?
        )>((0, 0, nil, [], nil, nil))

        let scheduler = TelemetryBackgroundTaskScheduler(
            begin: { _, expirationHandler in
                state.withLock { $0.expirationHandler = expirationHandler }
                return UIBackgroundTaskIdentifier(rawValue: 77)
            },
            end: { taskID in
                state.withLock { $0.endedTaskIDs.append(taskID) }
            }
        )

        let (coordinator, spool, cleanup) = try makeAsyncCoordinator(
            now: now,
            scheduler: scheduler
        ) { _, _, onCancel in
            onCancel {
                let continuation = state.withLock { s -> CheckedContinuation<Void, Never>? in
                    s.cancelledCount += 1
                    let cont = s.cancelledContinuation
                    s.cancelledContinuation = nil
                    return cont
                }
                continuation?.resume()
            }
            let continuation = state.withLock { s -> CheckedContinuation<Void, Never>? in
                s.startedCount += 1
                let cont = s.startedContinuation
                s.startedContinuation = nil
                return cont
            }
            continuation?.resume()
        }
        defer { cleanup() }

        spool.append(makeRecord(seq: 1, level: .info, name: "held_upload"), now: now)

        let foregroundTask: Task<Void, Never>? =
            startForegroundFirst
            ? Task { @MainActor in
                await withDependencies {
                    $0.date.now = now
                } operation: {
                    await coordinator.flush(manual: false)
                }
            }
            : nil

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyStarted = state.withLock { s -> Bool in
                if s.startedCount > 0 { return true }
                s.startedContinuation = continuation
                return false
            }
            if alreadyStarted {
                continuation.resume()
            } else if !startForegroundFirst {
                coordinator.handleBackground()
            }
        }

        if startForegroundFirst {
            coordinator.handleBackground()
            // Yield so handleBackground's upload task enters flush and awaits activeFlushTask.
            await Task.yield()
        }

        let handler = try #require(state.withLock { $0.expirationHandler })
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyCancelled = state.withLock { s -> Bool in
                if s.cancelledCount > 0 { return true }
                s.cancelledContinuation = continuation
                return false
            }
            if alreadyCancelled {
                continuation.resume()
            } else {
                handler()
            }
        }

        if let foregroundTask {
            await foregroundTask.value
        }

        try await waitUntil {
            !coordinator.isUploading && state.withLock { !$0.endedTaskIDs.isEmpty }
        }

        #expect(state.withLock { $0.cancelledCount } == 1)
        #expect(state.withLock { $0.endedTaskIDs } == [UIBackgroundTaskIdentifier(rawValue: 77)])
        #expect(!coordinator.isUploading)
        #expect(coordinator.lastUploadError == nil)
        #expect(spool.listSealedSegments().count == 1)
    }

    @Test func coordinatorSchedulesAutomaticRetryOnBackoffWithoutAnotherWriteOrForeground() async throws {
        let start = try Date("2026-10-01T12:00:00Z", strategy: .iso8601)
        let currentNow = Mutex(start)
        let clock = TestClock()
        let attempts = Mutex(0)

        let dir = makeTempDirectory()
        let suiteName = "in.bitehaus.clinical.retry.test.\(UUID().uuidString)"
        let sharedDefaults = try #require(UserDefaults(suiteName: suiteName))
        let standardSuiteName = "in.bitehaus.clinical.retry.std.\(UUID().uuidString)"
        let standardDefaults = try #require(UserDefaults(suiteName: standardSuiteName))
        let spool = TelemetrySpool(directory: dir, mirrorsToOSLog: false)
        let settings = TelemetrySettingsStore(
            sharedDefaults: sharedDefaults,
            standardDefaults: standardDefaults
        )
        let tokenKey = UUID().uuidString
        let scriptedResponses: [(Int, [String: String]?)] = [
            (500, nil),
            (200, nil),
            (429, ["Retry-After": "120"]),
            (200, nil),
            (200, nil),
            (500, nil),
        ]
        TelemetryMockURLProtocol.register(key: tokenKey) { request in
            let attempt = attempts.withLock { value -> Int in
                value += 1
                return value
            }
            let (status, headers) =
                attempt <= scriptedResponses.count ? scriptedResponses[attempt - 1] : (500, nil)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            let body = status == 200 ? Data("{\"ingested\":1,\"failed\":0}".utf8) : Data()
            return (response, body)
        }
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [TelemetryMockURLProtocol.self]
        sessionConfig.httpAdditionalHeaders = ["X-Telemetry-Test-Key": tokenKey]
        let session = URLSession(configuration: sessionConfig)
        let config = TelemetryConfiguration(
            ingestURL: URL(string: "https://api.axiom.co/v1/datasets/clinical-dev/ingest"),
            dataset: "clinical-dev",
            ingestToken: "test-token",
            environment: .dev,
            isUploadEnabled: true
        )
        let backgroundEnded = Mutex(false)
        let scheduler = TelemetryBackgroundTaskScheduler(
            begin: { _, _ in UIBackgroundTaskIdentifier(rawValue: 99) },
            end: { _ in backgroundEnded.withLock { $0 = true } }
        )
        let coordinator = withDependencies {
            $0.date = DateGenerator { currentNow.withLock { $0 } }
            $0.continuousClock = clock
            $0.telemetryBackgroundTaskScheduler = scheduler
        } operation: {
            TelemetryCoordinator(
                spool: spool,
                settings: settings,
                configuration: config,
                session: session,
                normalFlushDelay: .milliseconds(500),
                errorFlushDelay: .milliseconds(100),
                attachWriteHook: true
            )
        }
        defer {
            TelemetryMockURLProtocol.unregister(key: tokenKey)
            session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: dir)
            sharedDefaults.removePersistentDomain(forName: suiteName)
            standardDefaults.removePersistentDomain(forName: standardSuiteName)
        }

        // Write a record, let the debounced flush hit a transient 500, then let the scheduled retry
        // succeed at the 30s backoff deadline without another write or foreground event.
        spool.append(makeRecord(seq: 1, level: .info, name: "transient_500"), now: start)
        await Task.yield()

        let afterDebounce = start.addingTimeInterval(0.5)
        currentNow.withLock { $0 = afterDebounce }
        await clock.advance(by: .milliseconds(500))
        try await waitUntil { attempts.withLock { $0 } >= 1 && !coordinator.isUploading }

        #expect(attempts.withLock { $0 } == 1)
        #expect(coordinator.backoffUntil == afterDebounce.addingTimeInterval(30))
        #expect(spool.listSealedSegments().count == 1)

        let afterBackoff = afterDebounce.addingTimeInterval(30)
        currentNow.withLock { $0 = afterBackoff }
        await clock.advance(by: .seconds(30))
        try await waitUntil { attempts.withLock { $0 } >= 2 && !coordinator.isUploading }

        #expect(attempts.withLock { $0 } == 2)
        #expect(coordinator.backoffUntil == nil)
        #expect(coordinator.lastUploadError == nil)
        #expect(spool.listSealedSegments().isEmpty)

        // Now verify 429 Retry-After schedules a retry, and an earlier debounce does not bypass or
        // break the scheduled 120s retry.
        spool.append(makeRecord(seq: 2, level: .info, name: "rate_limited"), now: afterBackoff)
        await Task.yield()
        let t1 = afterBackoff.addingTimeInterval(0.5)
        currentNow.withLock { $0 = t1 }
        await clock.advance(by: .milliseconds(500))
        try await waitUntil { attempts.withLock { $0 } >= 3 && !coordinator.isUploading }

        #expect(attempts.withLock { $0 } == 3)
        #expect(coordinator.backoffUntil == t1.addingTimeInterval(120))

        // Trigger a faster error debounce before the 120s deadline.
        spool.append(makeRecord(seq: 3, level: .error, name: "early_error"), now: t1.addingTimeInterval(1))
        await Task.yield()
        let t2 = t1.addingTimeInterval(2)
        currentNow.withLock { $0 = t2 }
        await clock.advance(by: .seconds(1))
        await Task.yield()
        #expect(attempts.withLock { $0 } == 3)

        let afterRetryAfter = t1.addingTimeInterval(120)
        currentNow.withLock { $0 = afterRetryAfter }
        await clock.advance(by: .seconds(119))
        try await waitUntil { attempts.withLock { $0 } >= 5 && !coordinator.isUploading }

        #expect(attempts.withLock { $0 } == 5)
        #expect(coordinator.backoffUntil == nil)
        #expect(coordinator.lastUploadError == nil)
        #expect(spool.listSealedSegments().isEmpty)

        // Backgrounding cancels any pending active-app retry timer and does not schedule a new
        // retry timer if the background flush fails.
        spool.append(makeRecord(seq: 4, level: .info, name: "bg_cancel"), now: afterRetryAfter)
        await Task.yield()
        let t3 = afterRetryAfter.addingTimeInterval(0.5)
        currentNow.withLock { $0 = t3 }
        await clock.advance(by: .milliseconds(500))
        try await waitUntil { attempts.withLock { $0 } >= 6 && !coordinator.isUploading }
        #expect(attempts.withLock { $0 } == 6)

        coordinator.handleBackground()
        try await waitUntil { backgroundEnded.withLock { $0 } }
        let t4 = t3.addingTimeInterval(60)
        currentNow.withLock { $0 = t4 }
        await clock.advance(by: .seconds(60))
        await Task.yield()
        #expect(attempts.withLock { $0 } == 6)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func verboseLoggingAutoExpiresAfterTwentyFourHours() throws {
        let start = try Date("2026-10-01T08:00:00Z", strategy: .iso8601)
        let suiteName = "in.bitehaus.clinical.verbose.test.\(UUID().uuidString)"
        let sharedDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { sharedDefaults.removePersistentDomain(forName: suiteName) }

        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = TelemetrySettingsStore(sharedDefaults: sharedDefaults)
        let spool = TelemetrySpool(directory: dir, mirrorsToOSLog: false)
        let config = TelemetryConfiguration(
            ingestURL: nil, dataset: "clinical-dev", ingestToken: "", environment: .dev,
            isUploadEnabled: false)

        let coordinator = withDependencies {
            $0.date.now = start
        } operation: {
            TelemetryCoordinator(
                spool: spool, settings: settings, configuration: config, attachWriteHook: false)
        }

        #expect(!coordinator.isVerboseEnabled)
        withDependencies {
            $0.date.now = start
        } operation: {
            coordinator.setVerboseEnabled(true)
            #expect(coordinator.isVerboseEnabled)
            #expect(settings.isVerboseEnabled(at: start.addingTimeInterval(23 * 3600)))
        }

        let afterExpiry = start.addingTimeInterval(24 * 3600 + 1)
        withDependencies {
            $0.date.now = afterExpiry
        } operation: {
            coordinator.refreshState()
            #expect(!coordinator.isVerboseEnabled)
            #expect(!settings.isVerboseEnabled(at: afterExpiry))
        }
    }

    @Test func metricKitParserExtractsDiagnosticsIntoFixedSchemaWithoutDynamicKeys() throws {
        let fixture: [String: Any] = [
            "timeStampBegin": "2026-10-01 10:00:00 +0000",
            "timeStampEnd": "2026-10-02 10:00:00 +0000",
            "crashDiagnostics": [
                [
                    "version": "1.0.0",
                    "diagnosticMetaData": [
                        "appBuildVersion": "42",
                        "osVersion": "iPhone OS 26.4",
                        "deviceType": "iPhone17,1",
                        "exceptionType": 6,
                        "exceptionCode": 0,
                        "signal": 6,
                        "terminationReason": "Namespace SIGNAL, Code 6 Abort trap: 6",
                    ],
                    "callStackTree": [
                        "callStackPerThread": true,
                        "callStacks": [
                            [
                                "threadAttributed": true,
                                "callStackRootFrames": [
                                    [
                                        "binaryName": "clinical-swift",
                                        "binaryUUID": "11111111-2222-3333-4444-555555555555",
                                        "offsetIntoBinaryTextSegment": 12345,
                                        "address": 4_294_979_641,
                                        "subFrames": [
                                            [
                                                "binaryName": "SwiftUI",
                                                "offsetIntoBinaryTextSegment": 67890,
                                            ]
                                        ],
                                    ]
                                ],
                            ]
                        ],
                    ],
                ]
            ],
            "hangDiagnostics": [
                [
                    "version": "1.0.0",
                    "diagnosticMetaData": [
                        "hangDuration": "1250 ms"
                    ],
                ]
            ],
        ]

        let fixtureData = try JSONSerialization.data(withJSONObject: fixture)
        let entries = MetricKitParser.parseDiagnosticPayload(fixtureData)
        #expect(entries.count == 2)

        let crash = entries[0]
        #expect(crash.kind == .metric)
        #expect(crash.category == .metrickit)
        #expect(crash.level == .fault)
        #expect(crash.name == "metrickit_crash")
        #expect(crash.errorCode == 6)
        #expect(crash.details?.contains("clinical-swift") == true)

        let hang = entries[1]
        #expect(hang.level == .error)
        #expect(hang.name == "metrickit_hang")
        #expect(hang.message?.contains("1250 ms") == true)

        // Encoding the resulting TelemetryRecord must emit ONLY fixed top-level keys.
        let allowedKeys = Set(TelemetryRecord.CodingKeys.allCases.map(\.rawValue))
        let settings = TelemetrySettingsStore(sharedDefaults: nil)
        let builder = TelemetryRecordBuilder(process: .app, environment: .dev, settings: settings)
        let record = builder.makeRecord(from: crash)
        let encoded = try JSONEncoder().encode(record)
        let jsonObject = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(jsonObject.keys).isSubset(of: allowedKeys))
    }

    // MARK: - Helpers

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "telemetry-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func makeRecord(
        seq: Int,
        level: TelemetryLevel,
        name: String,
        message: String? = nil,
        sql: String? = nil
    ) -> TelemetryRecord {
        TelemetryRecord(
            time: "2026-10-01T10:00:00.000Z",
            seq: seq,
            kind: .log,
            level: level,
            category: .telemetry,
            name: name,
            message: message,
            sessionID: "session-test",
            deviceID: "device-test",
            process: .app,
            env: .dev,
            appVersion: "1.0",
            buildNumber: "1",
            osVersion: "26.4.0",
            deviceModel: "iPhone17,1",
            sql: sql
        )
    }

    @Test func liveRuntimeDropsDebugEntriesWhenVerboseIsDisabled() throws {
        let dir = makeTempDirectory()
        let suiteName = "in.bitehaus.clinical.runtime.debug.test.\(UUID().uuidString)"
        let sharedDefaults = try #require(UserDefaults(suiteName: suiteName))
        let standardSuiteName = "in.bitehaus.clinical.runtime.debug.std.\(UUID().uuidString)"
        let standardDefaults = try #require(UserDefaults(suiteName: standardSuiteName))
        defer {
            try? FileManager.default.removeItem(at: dir)
            sharedDefaults.removePersistentDomain(forName: suiteName)
            standardDefaults.removePersistentDomain(forName: standardSuiteName)
        }

        let settings = TelemetrySettingsStore(
            sharedDefaults: sharedDefaults,
            standardDefaults: standardDefaults
        )
        let spool = TelemetrySpool(directory: dir, mirrorsToOSLog: false)
        let runtime = TelemetryLiveRuntime(
            configuration: TelemetryConfiguration(
                ingestURL: nil,
                dataset: "clinical-dev",
                ingestToken: "",
                environment: .dev,
                isUploadEnabled: false
            ),
            settings: settings,
            spool: spool,
            builder: TelemetryRecordBuilder(
                process: .app,
                environment: .dev,
                settings: settings
            )
        )

        let start = try Date("2026-10-01T10:00:00Z", strategy: .iso8601)
        runtime.record(
            TelemetryEntry(
                kind: .event,
                level: .debug,
                category: .schedule,
                name: "schedule_window_loaded"
            ),
            now: start
        )
        runtime.record(
            TelemetryEntry(
                kind: .event,
                level: .info,
                category: .navigation,
                name: "tab_selected"
            ),
            now: start
        )

        settings.setVerboseEnabled(true, now: start)
        runtime.record(
            TelemetryEntry(
                kind: .event,
                level: .debug,
                category: .schedule,
                name: "schedule_window_loaded"
            ),
            now: start.addingTimeInterval(60)
        )

        // After 24 hours verbose auto-expires and debug entries drop again.
        let afterExpiry = start.addingTimeInterval(TelemetrySettingsStore.verboseDuration + 1)
        runtime.record(
            TelemetryEntry(
                kind: .event,
                level: .debug,
                category: .schedule,
                name: "schedule_window_loaded"
            ),
            now: afterExpiry
        )

        let exportURL = dir.appending(path: "export.ndjson")
        let count = try spool.exportNDJSON(to: exportURL, now: afterExpiry)
        #expect(count == 2)
        let lines = try String(contentsOf: exportURL, encoding: .utf8)
            .split(separator: "\n")
        let decoded: [TelemetryRecord] = try lines.map { line in
            try JSONDecoder().decode(TelemetryRecord.self, from: Data(line.utf8))
        }
        #expect(decoded.map(\.name) == ["tab_selected", "schedule_window_loaded"])
        #expect(decoded.map(\.level) == [.info, .debug])
    }

    private func makeCoordinator(
        now: Date,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) throws -> (TelemetryCoordinator, TelemetrySpool, () -> Void) {
        try makeAsyncCoordinator(now: now) { request, complete, _ in
            do {
                complete(.success(try handler(request)))
            } catch {
                complete(.failure(error))
            }
        }
    }

    private func makeAsyncCoordinator(
        now: Date,
        scheduler: TelemetryBackgroundTaskScheduler = .testValue,
        asyncHandler: @escaping TelemetryMockURLProtocol.AsyncHandler
    ) throws -> (TelemetryCoordinator, TelemetrySpool, () -> Void) {
        let dir = makeTempDirectory()
        let suiteName = "in.bitehaus.clinical.coord.async.test.\(UUID().uuidString)"
        let sharedDefaults = try #require(UserDefaults(suiteName: suiteName))
        let standardSuiteName = "in.bitehaus.clinical.coord.async.std.\(UUID().uuidString)"
        let standardDefaults = try #require(UserDefaults(suiteName: standardSuiteName))

        let spool = TelemetrySpool(directory: dir, mirrorsToOSLog: false)
        let settings = TelemetrySettingsStore(
            sharedDefaults: sharedDefaults,
            standardDefaults: standardDefaults
        )
        let tokenKey = UUID().uuidString
        TelemetryMockURLProtocol.registerAsync(key: tokenKey, handler: asyncHandler)
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [TelemetryMockURLProtocol.self]
        sessionConfig.httpAdditionalHeaders = ["X-Telemetry-Test-Key": tokenKey]
        let session = URLSession(configuration: sessionConfig)

        let config = TelemetryConfiguration(
            ingestURL: URL(string: "https://api.axiom.co/v1/datasets/clinical-dev/ingest"),
            dataset: "clinical-dev",
            ingestToken: "test-token",
            environment: .dev,
            isUploadEnabled: true
        )
        let coordinator = withDependencies {
            $0.date.now = now
            $0.continuousClock = TestClock()
            $0.telemetryBackgroundTaskScheduler = scheduler
        } operation: {
            TelemetryCoordinator(
                spool: spool,
                settings: settings,
                configuration: config,
                session: session,
                attachWriteHook: false
            )
        }
        let cleanup: () -> Void = {
            TelemetryMockURLProtocol.unregister(key: tokenKey)
            session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: dir)
            sharedDefaults.removePersistentDomain(forName: suiteName)
            standardDefaults.removePersistentDomain(forName: standardSuiteName)
        }
        return (coordinator, spool, cleanup)
    }

    nonisolated private static func readHTTPBody(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }
}

private nonisolated final class TelemetryMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    typealias Completion = @Sendable (Result<(HTTPURLResponse, Data), any Error>) -> Void
    typealias AsyncHandler = @Sendable (
        URLRequest,
        @escaping Completion,
        _ registerCancel: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void
    ) -> Void

    private static let handlers = Mutex<[String: AsyncHandler]>([:])

    private struct LoadingState {
        var finished = false
        var onCancel: (@Sendable () -> Void)?
    }

    private let loadingState = Mutex(LoadingState())

    static func register(key: String, handler: @escaping Handler) {
        registerAsync(key: key) { request, complete, _ in
            do {
                complete(.success(try handler(request)))
            } catch {
                complete(.failure(error))
            }
        }
    }

    static func registerAsync(key: String, handler: @escaping AsyncHandler) {
        handlers.withLock { $0[key] = handler }
    }

    static func unregister(key: String) {
        _ = handlers.withLock { $0.removeValue(forKey: key) }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let key = request.value(forHTTPHeaderField: "X-Telemetry-Test-Key"),
            let handler = Self.handlers.withLock({ $0[key] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        handler(
            request,
            { [weak self] result in
                guard let self else { return }
                let shouldFinish = self.loadingState.withLock { state -> Bool in
                    guard !state.finished else { return false }
                    state.finished = true
                    return true
                }
                guard shouldFinish else { return }
                switch result {
                case .success(let (response, data)):
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    self.client?.urlProtocol(self, didLoad: data)
                    self.client?.urlProtocolDidFinishLoading(self)
                case .failure(let error):
                    self.client?.urlProtocol(self, didFailWithError: error)
                }
            },
            { [weak self] onCancel in
                guard let self else { return }
                let alreadyFinished = self.loadingState.withLock { state -> Bool in
                    if state.finished { return true }
                    state.onCancel = onCancel
                    return false
                }
                if alreadyFinished {
                    onCancel()
                }
            }
        )
    }

    override func stopLoading() {
        let onCancel = loadingState.withLock { state -> (@Sendable () -> Void)? in
            guard !state.finished else { return nil }
            state.finished = true
            return state.onCancel
        }
        guard let onCancel else { return }
        onCancel()
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
}
