import ClinicalModels
import ClinicalPersistence
import Foundation
import GRDB
import SQLiteData
import Testing

struct DatabaseConfigurationTests {
    @Test func defaultUUIDsWorkOnWriterAndReaderConnections() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try DatabasePool(
            path: directory.appending(path: "test.db").path(),
            configuration: clinicalDatabaseConfiguration()
        )
        defer { try? database.close() }
        try migrateDatabase(database)

        try database.write { db in
            // Omit IDs to exercise the schema defaults rather than the domain's UUID initializer.
            try db.execute(
                sql: """
                    INSERT INTO patients (name, createdAt, updatedAt)
                    VALUES ('First', '2026-10-23 09:00:00', '2026-10-23 09:00:00'),
                           ('Second', '2026-10-23 09:00:00', '2026-10-23 09:00:00')
                    """)
        }
        try database.read { db in
            let patients = try PatientRecord.all.fetchAll(db)
            #expect(patients.count == 2)
            #expect(Set(patients.map(\.id)).count == 2)
            let readerUUID = try #require(try String.fetchOne(db, sql: "SELECT uuid()"))
            #expect(UUID(uuidString: readerUUID) != nil)
            #expect(try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") == true)
        }
    }
}
