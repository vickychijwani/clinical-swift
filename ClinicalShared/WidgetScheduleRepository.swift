import Dependencies
import Foundation
import GRDB

nonisolated struct WidgetScheduleSection: Identifiable, Sendable {
    let date: Date
    let isToday: Bool
    let appointments: [Appointment]

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

        let nextAppointmentEnd =
            sections
            .flatMap(\.appointments)
            .map { $0.end(using: calendar) }
            .filter { $0 > generatedAt }
            .min()

        return min(nextAppointmentEnd ?? nextMidnight, nextMidnight)
    }
}

nonisolated struct WidgetScheduleRepository: Sendable {
    @Dependency(\.calendar) private var calendar
    let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func snapshot(at now: Date) throws -> WidgetScheduleSnapshot? {
        guard let database = try ClinicalSharedDatabase.openReadOnly(at: databaseURL) else {
            return nil
        }
        return try snapshot(in: database, at: now)
    }

    func snapshot(
        in database: any DatabaseReader,
        at now: Date
    ) throws -> WidgetScheduleSnapshot {
        let today = calendar.startOfDay(for: now)
        let endExclusive = calendar.date(byAdding: .day, value: 3, to: today) ?? today
        let startValue = Self.databaseDateString(today)
        let endValue = Self.databaseDateString(endExclusive)

        let appointments = try database.read { database in
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

            return try rows.map(Self.appointment(from:))
        }
        .filter { $0.end(using: calendar) > now }

        let sections = (0..<3).compactMap { dayOffset -> WidgetScheduleSection? in
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                return nil
            }
            let sectionAppointments = appointments.filter {
                calendar.isDate($0.start, inSameDayAs: date)
            }

            return WidgetScheduleSection(
                date: date,
                isToday: dayOffset == 0,
                appointments: sectionAppointments
            )
        }

        return WidgetScheduleSnapshot(generatedAt: now, sections: sections)
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
}
