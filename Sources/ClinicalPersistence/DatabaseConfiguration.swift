import Foundation
import GRDB

public func clinicalDatabaseConfiguration() -> Configuration {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    #if os(Linux)
        configuration.prepareDatabase { db in
            // Apple's SQLite provides uuid(); Linux needs it on each writer and reader connection.
            db.add(
                function: DatabaseFunction("uuid", argumentCount: 0, pure: false) { _ in
                    UUID().uuidString.lowercased()
                })
        }
    #endif
    return configuration
}
