import ClinicalPersistence
import GRDB

nonisolated func testDatabase(path: String = ":memory:") throws -> DatabaseQueue {
    let database = try DatabaseQueue(path: path, configuration: clinicalDatabaseConfiguration())
    try migrateDatabase(database)
    return database
}
