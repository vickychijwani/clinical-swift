import ClinicalModels
import ClinicalPersistence
import Foundation
import GRDB

@testable import clinical_swift

@MainActor
enum BackupFixture {
    static let capturedAt = try! Date("2026-10-11T12:00:00Z", strategy: .iso8601)
    static let datasetID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

    static func directory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "backup tests " + UUID().uuidString)
        try BackupFiles.createDirectory(url)
        return url
    }

    static func database(at url: URL) throws -> DatabasePool {
        let database = try DatabasePool(
            path: url.path(percentEncoded: false), configuration: clinicalDatabaseConfiguration())
        try databaseMigrator(allowDebugErasure: false).migrate(database)
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO patients VALUES
                    ('10000000-0000-0000-0000-000000000001', 'Synthetic Patient', '+919876543210', '1990-02-03 00:00:00.000', 'female', '2020-01-01 00:00:00', '2026-10-10 01:02:03.456'),
                    ('10000000-0000-0000-0000-000000000002', NULL, NULL, NULL, NULL, '2020-01-02 00:00:00', '2020-01-02 00:00:00');
                    INSERT INTO appointments VALUES
                    ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '2026-10-10 10:30:00', 45, 'scheduled', '2026-01-01 00:00:00', '2026-10-10 00:00:00'),
                    ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '2020-01-01 10:00:00', 30, 'completed', '2020-01-01 00:00:00', '2020-01-01 00:00:00'),
                    ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '2040-01-01 10:00:00', 60, 'cancelled', '2026-01-01 00:00:00', '2026-10-01 00:00:00');
                    INSERT INTO unavailableTimes VALUES
                    ('30000000-0000-0000-0000-000000000001', 'Synthetic block', '2026-10-03 23:30:00', 30, '2026-01-01 00:00:00', '2026-10-01 00:00:00'),
                    ('30000000-0000-0000-0000-000000000002', NULL, '2020-01-01 00:00:00', 30, '2020-01-01 00:00:00', '2020-01-01 00:00:00');
                    INSERT INTO accountEntries VALUES
                    ('50000000-0000-0000-0000-000000000001', 'charge', 5000, '2026-10-09 18:30:00.000', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', NULL, 'Synthetic charge', NULL, '2026-10-10 10:00:00.000', '2026-10-10 10:00:00.000'),
                    ('50000000-0000-0000-0000-000000000002', 'receipt', 3000, '2026-10-09 18:30:00.000', '10000000-0000-0000-0000-000000000001', NULL, 'patientFees', NULL, 'upi', '2026-10-10 10:01:00.000', '2026-10-10 10:01:00.000'),
                    ('50000000-0000-0000-0000-000000000003', 'adjustment', -1000, '2026-10-09 18:30:00.000', '10000000-0000-0000-0000-000000000001', NULL, NULL, 'Incomplete history', NULL, '2026-10-10 10:02:00.000', '2026-10-10 10:02:00.000'),
                    ('50000000-0000-0000-0000-000000000004', 'expense', 200, '2026-10-09 18:30:00.000', NULL, NULL, 'materials', 'Synthetic expense', 'cash', '2026-10-10 10:03:00.000', '2026-10-10 10:03:00.000');
                    UPDATE appointmentCalendarSync SET eventIdentifier = 'old-event-id', eventStart = '2026-10-12 10:00:00', needsSync = 0, revision = 9;
                    INSERT INTO appointmentCalendarSync VALUES
                    ('40000000-0000-0000-0000-000000000001', 'deleted-recent', '2026-10-05 00:00:00', 1, 3, '2026-01-01 00:00:00', '2026-10-01 00:00:00'),
                    ('40000000-0000-0000-0000-000000000002', 'deleted-old', '2020-01-01 00:00:00', 1, 4, '2020-01-01 00:00:00', '2020-01-01 00:00:00'),
                    ('40000000-0000-0000-0000-000000000003', NULL, NULL, 1, 1, '2020-01-01 00:00:00', '2020-01-01 00:00:00');
                    """)
            // This committed update remains in the source WAL at capture time.
            try db.execute(
                sql: "UPDATE patients SET name = 'Synthetic WAL update' WHERE phone IS NOT NULL")
        }
        return database
    }

    // SQL quote preserves NULL, numeric, and text storage values for every column.
    nonisolated static func contents(_ database: any DatabaseReader) throws -> [String: [[String]]]
    {
        try database.read { try contents($0) }
    }

    nonisolated static func contents(_ db: Database) throws -> [String: [[String]]] {
        let tables = try String.fetchAll(
            db,
            sql:
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        )
        var result: [String: [[String]]] = [:]
        for table in tables {
            let quotedTable = "\"" + table.replacing("\"", with: "\"\"") + "\""
            let columns = try db.columns(in: table).map {
                "quote(\"" + $0.name.replacing("\"", with: "\"\"") + "\")"
            }
            let rows = try Row.fetchAll(
                db, sql: "SELECT " + columns.joined(separator: ",") + " FROM " + quotedTable)
            result[table] = rows.map { row in (0..<row.count).map { row[$0] as String } }.sorted {
                $0.lexicographicallyPrecedes($1)
            }
        }
        return result
    }
}
