import ClinicalModels
import Dependencies
import Foundation

/// Resolved Axiom ingest configuration from Info.plist and runtime execution context.
nonisolated struct TelemetryConfiguration: Equatable, Sendable {
    let ingestURL: URL?
    let dataset: String
    let ingestToken: String
    let environment: TelemetryEnvironment
    let isUploadEnabled: Bool

    static func isUITesting(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(where: { $0.hasPrefix("--ui-testing-") })
    }

    static func live(
        bundle: Bundle = .main,
        context: DependencyContext? = nil,
        arguments: [String] = CommandLine.arguments
    ) -> Self {
        let resolvedContext: DependencyContext
        if let context {
            resolvedContext = context
        } else {
            @Dependency(\.context) var currentContext
            resolvedContext = currentContext
        }
        return resolve(
            infoDictionary: bundle.infoDictionary ?? [:],
            context: resolvedContext,
            arguments: arguments
        )
    }

    static func resolve(
        infoDictionary: [String: Any],
        context: DependencyContext,
        arguments: [String] = CommandLine.arguments
    ) -> Self {
        let rawDataset = sanitizedString(infoDictionary["AxiomIngestDataset"])
        let rawToken = sanitizedString(infoDictionary["AxiomIngestToken"])
        let rawURL = sanitizedString(infoDictionary["AxiomIngestURL"])

        let environment: TelemetryEnvironment =
            if !rawDataset.isEmpty {
                rawDataset.hasSuffix("-prod") ? .prod : .dev
            } else {
                TelemetryRuntime.defaultEnvironment
            }

        let ingestURL = buildIngestURL(rawURL: rawURL, dataset: rawDataset)
        let isUploadEnabled =
            context == .live
            && !isUITesting(arguments: arguments)
            && ingestURL != nil
            && !rawDataset.isEmpty
            && !rawToken.isEmpty

        return Self(
            ingestURL: ingestURL,
            dataset: rawDataset,
            ingestToken: rawToken,
            environment: environment,
            isUploadEnabled: isUploadEnabled
        )
    }

    private static func sanitizedString(_ value: Any?) -> String {
        guard let string = value as? String else { return "" }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return "" }
        return trimmed
    }

    private static func buildIngestURL(rawURL: String, dataset: String) -> URL? {
        guard !rawURL.isEmpty, !dataset.isEmpty else { return nil }
        let expanded = rawURL.replacing("{dataset}", with: dataset)
        guard var components = URLComponents(string: expanded),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            let host = components.host, !host.isEmpty
        else { return nil }

        // Support both full endpoint URLs (legacy or regional edge) and bare base URLs.
        if components.path.isEmpty || components.path == "/" {
            components.path = "/v1/datasets/\(dataset)/ingest"
        }
        return components.url
    }
}
