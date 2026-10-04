import Foundation
import SQLiteData

@Table("unavailableTimes")
nonisolated struct UnavailableTimeRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    var label: String?
    var start: Date
    var durationMinutes: Int
    var createdAt: Date
    var updatedAt: Date

    var unavailableTime: UnavailableTime {
        UnavailableTime(id: id, label: label, start: start, durationMinutes: durationMinutes)
    }
}

nonisolated func unavailableTimesQuery(
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
        .selectStar()
}

/// Device-local work survives source deletion. Exclude this table from cross-device sync.
@Table("unavailableTimeCalendarSync")
nonisolated struct UnavailableTimeCalendarSyncRecord: Equatable, Sendable {
    @Column(primaryKey: true)
    let unavailableTimeID: UUID
    var eventIdentifier: String?
    var eventStart: Date?
    var needsSync: Bool
    var revision: Int
    var createdAt: Date
    var updatedAt: Date
}
