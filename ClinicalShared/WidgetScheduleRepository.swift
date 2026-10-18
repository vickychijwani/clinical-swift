import Dependencies
import Foundation
import GRDB

nonisolated struct WidgetScheduleSection: Identifiable, Sendable {
    let date: Date
    let isToday: Bool
    let items: [TimelineItem]

    init(date: Date, isToday: Bool, items: [TimelineItem]) {
        self.date = date
        self.isToday = isToday
        self.items = items.sorted(by: TimelineItem.ordered)
    }

    init(date: Date, isToday: Bool, appointments: [Appointment]) {
        self.init(date: date, isToday: isToday, items: appointments.map(TimelineItem.appointment))
    }

    var appointments: [Appointment] {
        items.compactMap {
            guard case .appointment(let appointment) = $0 else { return nil }
            return appointment
        }
    }

    func overflowText(hiddenCount: Int) -> String {
        let appointmentOnly = items.suffix(hiddenCount).allSatisfy {
            if case .appointment = $0 { return true }
            return false
        }
        if appointmentOnly {
            return hiddenCount == 1 ? "1 more appointment" : "\(hiddenCount) more appointments"
        }
        return hiddenCount == 1 ? "1 more item" : "\(hiddenCount) more items"
    }

    var id: Date { date }
}

nonisolated struct WidgetScheduleSnapshot: Sendable {
    let generatedAt: Date
    let sections: [WidgetScheduleSection]

    func nextRefreshDate(using calendar: Calendar) -> Date {
        let nextMidnight =
            calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: generatedAt)
            ) ?? generatedAt.addingTimeInterval(60 * 60)

        let nextItemEnd =
            sections
            .flatMap(\.items)
            .map { $0.end(using: calendar) }
            .filter { $0 > generatedAt }
            .min()

        return min(nextItemEnd ?? nextMidnight, nextMidnight)
    }
}

nonisolated struct WidgetScheduleRepository: Sendable {
    @Dependency(\.calendar) private var calendar
    let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func snapshot(at now: Date) throws -> WidgetScheduleSnapshot? {
        try ClinicalSharedDatabase.read(at: databaseURL) { database in
            try snapshot(in: database, at: now)
        }
    }

    func snapshot(
        in database: any DatabaseReader,
        at now: Date
    ) throws -> WidgetScheduleSnapshot {
        try database.read { try snapshot(in: $0, at: now) }
    }

    private func snapshot(in database: Database, at now: Date) throws -> WidgetScheduleSnapshot {
        let today = calendar.startOfDay(for: now)
        let endExclusive = calendar.date(byAdding: .day, value: 3, to: today) ?? today
        let startValue = Self.databaseDateString(today)
        let endValue = Self.databaseDateString(endExclusive)

        let items = try items(in: database, startValue: startValue, endValue: endValue)
            .filter { $0.end(using: calendar) > now }

        let sections = (0..<3).compactMap { dayOffset -> WidgetScheduleSection? in
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                return nil
            }
            let sectionItems = items.filter {
                calendar.isDate($0.start, inSameDayAs: date)
            }

            return WidgetScheduleSection(
                date: date,
                isToday: dayOffset == 0,
                items: sectionItems
            )
        }

        return WidgetScheduleSnapshot(generatedAt: now, sections: sections)
    }

    private func items(in database: Database, startValue: String, endValue: String) throws
        -> [TimelineItem]
    {
        let rows = try Row.fetchAll(
            database,
            // This is a raw SQL query because making it type-safe would require moving Record
            // types into the shared target and adding SQLite to the widget target.
            sql: """
                SELECT
                  appointments.id AS appointmentID,
                  appointments.start,
                  appointments.durationMinutes,
                  appointments.status,
                  patients.name AS patientName
                FROM appointments
                JOIN patients ON patients.id = appointments.patientID
                WHERE appointments.status <> ?
                  AND appointments.start >= ?
                  AND appointments.start < ?
                ORDER BY appointments.start ASC
                """,
            arguments: [
                Appointment.Status.cancelled.rawValue,
                startValue,
                endValue,
            ]
        )

        let appointments = try rows.map(Self.appointment(from:)).map(TimelineItem.appointment)
        // A widget can open the old schema before the app has run its new migration.
        let blocks: [TimelineItem]
        if try database.tableExists("unavailableTimes") {
            blocks = try Row.fetchAll(
                database,
                sql: """
                    SELECT id, label, start, durationMinutes FROM unavailableTimes
                    WHERE start >= ? AND start < ?
                    """,
                arguments: [startValue, endValue]
            ).map { row in
                let rawID: String = row["id"]
                guard let id = UUID(uuidString: rawID) else {
                    throw WidgetScheduleRepositoryError.invalidUnavailableTimeRow
                }
                return .unavailableTime(
                    UnavailableTime(
                        id: id, label: row["label"], start: row["start"],
                        durationMinutes: row["durationMinutes"]
                    ))
            }
        } else {
            blocks = []
        }
        return (appointments + blocks).sorted(by: TimelineItem.ordered)
    }

    private static func appointment(from row: Row) throws -> Appointment {
        let idString: String = row["appointmentID"]
        let statusString: String = row["status"]
        guard
            let id = UUID(uuidString: idString),
            let status = Appointment.Status(storageValue: statusString)
        else {
            throw WidgetScheduleRepositoryError.invalidAppointmentRow
        }

        let start: Date = row["start"]
        let durationMinutes: Int = row["durationMinutes"]
        let patientName: String? = row["patientName"]
        return Appointment(
            id: id,
            patientName: PatientDisplayName.resolve(patientName),
            start: start,
            durationMinutes: durationMinutes,
            status: status
        )
    }

    private static func databaseDateString(_ date: Date) -> String {
        date.formatted(
            .iso8601
                .year()
                .month()
                .day()
                .dateTimeSeparator(.space)
                .time(includingFractionalSeconds: true)
        )
    }
}

nonisolated enum WidgetScheduleRepositoryError: Error, Equatable, Sendable {
    case invalidAppointmentRow
    case invalidUnavailableTimeRow
}
