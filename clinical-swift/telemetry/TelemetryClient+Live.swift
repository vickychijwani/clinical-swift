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

    private init() {
        let configuration = TelemetryConfiguration.live(context: .live)
        let settings = TelemetrySettingsStore()
        let directory =
            TelemetrySpool.defaultDirectory(environment: configuration.environment)
            ?? FileManager.default.temporaryDirectory
            .appending(path: "Telemetry", directoryHint: .isDirectory)
            .appending(path: configuration.environment.rawValue, directoryHint: .isDirectory)
        self.configuration = configuration
        self.settings = settings
        self.spool = TelemetrySpool(directory: directory)
        self.builder = TelemetryRecordBuilder(
            process: .app,
            environment: configuration.environment,
            settings: settings
        )
    }
}

nonisolated extension TelemetryClient: @retroactive DependencyKey {
    public nonisolated static let liveValue = Self(
        record: { entry in
            guard !TelemetryConfiguration.isUITesting() else { return }
            let runtime = TelemetryLiveRuntime.shared
            let record = runtime.builder.makeRecord(from: entry)
            runtime.spool.append(record)
        },
        isVerboseEnabled: {
            guard !TelemetryConfiguration.isUITesting() else { return false }
            return TelemetryLiveRuntime.shared.settings.isVerboseEnabled()
        }
    )
}
