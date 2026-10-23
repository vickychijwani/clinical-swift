import ClinicalModels
import Foundation
import SQLiteData

@Table("unavailableTimes")
public nonisolated struct UnavailableTimeRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var label: String?
    public var start: Date
    public var durationMinutes: Int
    public var createdAt: Date
    public var updatedAt: Date

    public var unavailableTime: UnavailableTime {
        UnavailableTime(id: id, label: label, start: start, durationMinutes: durationMinutes)
    }

    public init(
        id: UUID, label: String? = nil, start: Date, durationMinutes: Int, createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.label = label
        self.start = start
        self.durationMinutes = durationMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public nonisolated func unavailableTimesQuery(
    centeredOn date: Date,
    dayRadius: Int
) -> some Statement<UnavailableTimeRecord> & Sendable {
    let calendar = Calendar.autoupdatingCurrent
    let center = calendar.startOfDay(for: date)
    let radius = max(dayRadius, 1)
    let start = calendar.date(byAdding: .day, value: -radius, to: center) ?? center
    let end = calendar.date(byAdding: .day, value: radius + 1, to: center) ?? center
    return
        UnavailableTimeRecord
        .where { $0.start >= start }
        .where { $0.start < end }
        .order { ($0.start.asc(), $0.id.asc()) }
        .select { $0 }
}

/// Device-local work survives source deletion. Exclude this table from cross-device sync.
@Table("unavailableTimeCalendarSync")
public nonisolated struct UnavailableTimeCalendarSyncRecord: Equatable, Sendable {
    @Column(primaryKey: true)
    public let unavailableTimeID: UUID
    public var eventIdentifier: String?
    public var eventStart: Date?
    public var needsSync: Bool
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        unavailableTimeID: UUID, eventIdentifier: String? = nil, eventStart: Date? = nil,
        needsSync: Bool,
        revision: Int, createdAt: Date, updatedAt: Date
    ) {
        self.unavailableTimeID = unavailableTimeID
        self.eventIdentifier = eventIdentifier
        self.eventStart = eventStart
        self.needsSync = needsSync
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
