import ClinicalPersistence
import GRDB

nonisolated func testDatabase() throws -> DatabaseQueue {
    let database = try DatabaseQueue(configuration: clinicalDatabaseConfiguration())
    try migrateDatabase(database)
    return database
}
