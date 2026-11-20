import ClinicalModels
import Dependencies
import Foundation

/// Shared process-wide telemetry spool and settings used by both `TelemetryClient.liveValue`
/// and `TelemetryCoordinator` so early startup logs and later uploads share one pipeline.
nonisolated final class TelemetryLiveRuntime: Sendable {
    static let shared = TelemetryLiveRuntime()

    let configuration: TelemetryConfiguration
    let settings: TelemetrySettingsStore
    let spool: TelemetrySpool
    let builder: TelemetryRecordBuilder

    init(
        configuration: TelemetryConfiguration,
        settings: TelemetrySettingsStore,
        spool: TelemetrySpool,
        builder: TelemetryRecordBuilder
    ) {
        self.configuration = configuration
        self.settings = settings
        self.spool = spool
        self.builder = builder
    }

    private convenience init() {
        let configuration = TelemetryConfiguration.live(context: .live)
        let settings = TelemetrySettingsStore()
        let directory =
            TelemetrySpool.defaultDirectory(environment: configuration.environment)
            ?? FileManager.default.temporaryDirectory
            .appending(path: "Telemetry", directoryHint: .isDirectory)
            .appending(path: configuration.environment.rawValue, directoryHint: .isDirectory)
        self.init(
            configuration: configuration,
            settings: settings,
            spool: TelemetrySpool(directory: directory),
            builder: TelemetryRecordBuilder(
                process: .app,
                environment: configuration.environment,
                settings: settings
            )
        )
    }

    func record(_ entry: TelemetryEntry, now: Date = .now) {
        // Verbose mode gates all debug logs and events, not only SQL traces.
        if entry.level == .debug, !settings.isVerboseEnabled(at: now) {
            return
        }
        let record = builder.makeRecord(from: entry, now: now)
        spool.append(record, now: now)
    }
}

nonisolated extension TelemetryClient: @retroactive DependencyKey {
    public nonisolated static let liveValue = Self(
        record: { entry in
            guard !TelemetryConfiguration.isUITesting() else { return }
            TelemetryLiveRuntime.shared.record(entry)
        },
        isVerboseEnabled: {
            guard !TelemetryConfiguration.isUITesting() else { return false }
            return TelemetryLiveRuntime.shared.settings.isVerboseEnabled()
        }
    )
}
