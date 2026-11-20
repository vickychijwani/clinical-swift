import Dependencies
import Foundation

/// Top-level record category for the unified telemetry stream.
public enum TelemetryKind: String, Codable, Equatable, Sendable, CaseIterable {
    case log
    case event
    case metric
}

/// Severity levels for telemetry records.
public enum TelemetryLevel: String, Codable, Equatable, Sendable, CaseIterable {
    case debug
    case info
    case warning
    case error
    case fault
}

/// Fixed feature and subsystem categories for telemetry records.
public enum TelemetryCategory: String, Codable, Equatable, Sendable, CaseIterable {
    case startup
    case database
    case backup
    case calendar
    case schedule
    case appointment
    case unavailableTime = "unavailable_time"
    case patient
    case payment
    case navigation
    case intent
    case widget
    case telemetry
    case metrickit
}

/// Process that emitted a telemetry record.
public enum TelemetryProcess: String, Codable, Equatable, Sendable, CaseIterable {
    case app
    case widget
}

/// Target dataset environment for telemetry storage and upload.
public enum TelemetryEnvironment: String, Codable, Equatable, Sendable, CaseIterable {
    case dev
    case prod
}

/// One flat telemetry record with a fixed key set to stay well below Axiom's 256-field cap.
public struct TelemetryRecord: Codable, Equatable, Sendable {
    public static let timestampFormat = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true,
        timeZone: .gmt
    )
    public static let maxSQLBytes = 4096

    public var time: String
    public var id: String
    public var seq: Int
    public var kind: TelemetryKind
    public var level: TelemetryLevel
    public var category: TelemetryCategory
    public var name: String
    public var message: String?
    public var sessionID: String
    public var deviceID: String?
    public var process: TelemetryProcess
    public var env: TelemetryEnvironment
    public var appVersion: String
    public var buildNumber: String
    public var osVersion: String
    public var deviceModel: String
    public var errorType: String?
    public var errorDomain: String?
    public var errorCode: Int?
    public var errorMessage: String?
    public var durationMS: Int?
    public var count: Int?
    public var recordID: String?
    public var status: String?
    public var source: String?
    public var route: String?
    public var action: String?
    public var sql: String?
    public var details: String?

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case time = "_time"
        case id
        case seq
        case kind
        case level
        case category
        case name
        case message
        case sessionID = "session_id"
        case deviceID = "device_id"
        case process
        case env
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case errorType = "error_type"
        case errorDomain = "error_domain"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case durationMS = "duration_ms"
        case count
        case recordID = "record_id"
        case status
        case source
        case route
        case action
        case sql
        case details
    }

    public init(
        time: String,
        id: String = UUID().uuidString.lowercased(),
        seq: Int,
        kind: TelemetryKind,
        level: TelemetryLevel,
        category: TelemetryCategory,
        name: String,
        message: String? = nil,
        sessionID: String,
        deviceID: String? = nil,
        process: TelemetryProcess,
        env: TelemetryEnvironment,
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        deviceModel: String,
        errorType: String? = nil,
        errorDomain: String? = nil,
        errorCode: Int? = nil,
        errorMessage: String? = nil,
        durationMS: Int? = nil,
        count: Int? = nil,
        recordID: String? = nil,
        status: String? = nil,
        source: String? = nil,
        route: String? = nil,
        action: String? = nil,
        sql: String? = nil,
        details: String? = nil
    ) {
        self.time = time
        self.id = id
        self.seq = seq
        self.kind = kind
        self.level = level
        self.category = category
        self.name = name
        self.message = message
        self.sessionID = sessionID
        self.deviceID = deviceID
        self.process = process
        self.env = env
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.errorType = errorType
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.durationMS = durationMS
        self.count = count
        self.recordID = recordID
        self.status = status
        self.source = source
        self.route = route
        self.action = action
        self.sql = sql
        self.details = details
    }

    /// Truncates SQL text to a safe UTF-8 byte budget for verbose logging.
    public static func truncateSQL(_ sql: String, maxBytes: Int = maxSQLBytes) -> String {
        guard sql.utf8.count > maxBytes else { return sql }
        let suffix = "…[truncated]"
        let budget = max(0, maxBytes - suffix.utf8.count)
        var end = sql.startIndex
        var usedBytes = 0
        for index in sql.indices {
            let scalarBytes = sql[index].utf8.count
            if usedBytes + scalarBytes > budget { break }
            usedBytes += scalarBytes
            end = sql.index(after: index)
        }
        return String(sql[..<end]) + suffix
    }
}

/// Extracted error fields for flat telemetry storage.
public struct TelemetryErrorInfo: Equatable, Sendable {
    public let type: String
    public let domain: String
    public let code: Int
    public let message: String

    public init(_ error: any Error) {
        let nsError = error as NSError
        self.type = String(reflecting: Swift.type(of: error))
        self.domain = nsError.domain
        self.code = nsError.code
        self.message = error.localizedDescription
    }
}

/// Input payload passed to `TelemetryClient` before envelope metadata is attached.
public struct TelemetryEntry: Equatable, Sendable {
    public var kind: TelemetryKind
    public var level: TelemetryLevel
    public var category: TelemetryCategory
    public var name: String
    public var message: String?
    public var errorType: String?
    public var errorDomain: String?
    public var errorCode: Int?
    public var errorMessage: String?
    public var durationMS: Int?
    public var count: Int?
    public var recordID: String?
    public var status: String?
    public var source: String?
    public var route: String?
    public var action: String?
    public var sql: String?
    public var details: String?

    public init(
        kind: TelemetryKind,
        level: TelemetryLevel,
        category: TelemetryCategory,
        name: String,
        message: String? = nil,
        error: (any Error)? = nil,
        errorType: String? = nil,
        errorDomain: String? = nil,
        errorCode: Int? = nil,
        errorMessage: String? = nil,
        durationMS: Int? = nil,
        count: Int? = nil,
        recordID: String? = nil,
        status: String? = nil,
        source: String? = nil,
        route: String? = nil,
        action: String? = nil,
        sql: String? = nil,
        details: String? = nil
    ) {
        let errorInfo = error.map(TelemetryErrorInfo.init)
        self.kind = kind
        self.level = level
        self.category = category
        self.name = name
        self.message = message
        self.errorType = errorType ?? errorInfo?.type
        self.errorDomain = errorDomain ?? errorInfo?.domain
        self.errorCode = errorCode ?? errorInfo?.code
        self.errorMessage = errorMessage ?? errorInfo?.message
        self.durationMS = durationMS
        self.count = count
        self.recordID = recordID
        self.status = status
        self.source = source
        self.route = route
        self.action = action
        self.sql = sql
        self.details = details
    }
}

/// Dependency client for recording operational logs, domain events, and metrics.
public struct TelemetryClient: Sendable {
    public var record: @Sendable (TelemetryEntry) -> Void
    public var isVerboseEnabled: @Sendable () -> Bool

    public init(
        record: @escaping @Sendable (TelemetryEntry) -> Void,
        isVerboseEnabled: @escaping @Sendable () -> Bool
    ) {
        self.record = record
        self.isVerboseEnabled = isVerboseEnabled
    }

    public func log(
        _ level: TelemetryLevel,
        category: TelemetryCategory,
        name: String,
        message: String? = nil,
        error: (any Error)? = nil,
        durationMS: Int? = nil,
        count: Int? = nil,
        recordID: String? = nil,
        status: String? = nil,
        source: String? = nil,
        route: String? = nil,
        action: String? = nil,
        sql: String? = nil,
        details: String? = nil
    ) {
        record(
            TelemetryEntry(
                kind: .log,
                level: level,
                category: category,
                name: name,
                message: message,
                error: error,
                durationMS: durationMS,
                count: count,
                recordID: recordID,
                status: status,
                source: source,
                route: route,
                action: action,
                sql: sql,
                details: details
            )
        )
    }

    public func event(
        category: TelemetryCategory,
        name: String,
        level: TelemetryLevel = .info,
        message: String? = nil,
        durationMS: Int? = nil,
        count: Int? = nil,
        recordID: String? = nil,
        status: String? = nil,
        source: String? = nil,
        route: String? = nil,
        action: String? = nil,
        details: String? = nil
    ) {
        record(
            TelemetryEntry(
                kind: .event,
                level: level,
                category: category,
                name: name,
                message: message,
                durationMS: durationMS,
                count: count,
                recordID: recordID,
                status: status,
                source: source,
                route: route,
                action: action,
                details: details
            )
        )
    }

    public func metric(
        category: TelemetryCategory,
        name: String,
        level: TelemetryLevel = .info,
        message: String? = nil,
        errorCode: Int? = nil,
        durationMS: Int? = nil,
        count: Int? = nil,
        status: String? = nil,
        source: String? = nil,
        details: String? = nil
    ) {
        record(
            TelemetryEntry(
                kind: .metric,
                level: level,
                category: category,
                name: name,
                message: message,
                errorCode: errorCode,
                durationMS: durationMS,
                count: count,
                status: status,
                source: source,
                details: details
            )
        )
    }
}

extension TelemetryClient: TestDependencyKey {
    public static let testValue = Self(
        record: { _ in },
        isVerboseEnabled: { false }
    )

    public static let previewValue = Self(
        record: { _ in },
        isVerboseEnabled: { false }
    )
}

extension DependencyValues {
    public var telemetry: TelemetryClient {
        get { self[TelemetryClient.self] }
        set { self[TelemetryClient.self] = newValue }
    }
}
