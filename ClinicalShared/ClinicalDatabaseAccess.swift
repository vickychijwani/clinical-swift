import Darwin
import Foundation

/// Every live pool holds a shared lock. Restore needs the exclusive lock before changing files.
nonisolated final class ClinicalDatabaseAccess: @unchecked Sendable {
    private let descriptor: Int32

    init(databaseURL: URL, exclusive: Bool = false) throws {
        let lockURL = databaseURL.appendingPathExtension("access-lock")
        let descriptor = open(lockURL.path(percentEncoded: false), O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ClinicalSharedDatabaseError.databaseAccessUnavailable }
        guard flock(descriptor, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else {
            close(descriptor)
            throw ClinicalSharedDatabaseError.databaseAccessUnavailable
        }
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
