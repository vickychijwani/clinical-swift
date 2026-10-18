import Foundation
import Synchronization

/// Live writers and scoped reads prevent replacement in this process without holding a file lock.
nonisolated final class ClinicalDatabaseAccess: Sendable {
    private struct Access {
        var readers = 0
        var isReplacing = false
    }

    private static let accesses = Mutex<[URL: Access]>([:])
    private let databaseURL: URL
    private let exclusive: Bool

    init(databaseURL: URL, exclusive: Bool = false) throws {
        let databaseURL = databaseURL.standardizedFileURL.resolvingSymlinksInPath()
        let acquired = Self.accesses.withLock { accesses in
            var access = accesses[databaseURL, default: Access()]
            guard !access.isReplacing, !exclusive || access.readers == 0 else { return false }
            if exclusive {
                access.isReplacing = true
            } else {
                access.readers += 1
            }
            accesses[databaseURL] = access
            return true
        }
        guard acquired else { throw ClinicalSharedDatabaseError.databaseAccessUnavailable }
        self.databaseURL = databaseURL
        self.exclusive = exclusive
    }

    deinit {
        Self.accesses.withLock { accesses in
            guard var access = accesses[databaseURL] else { return }
            if exclusive {
                access.isReplacing = false
            } else {
                access.readers -= 1
            }
            accesses[databaseURL] = access.readers == 0 && !access.isReplacing ? nil : access
        }
    }

    /// Coordinate the full replacement with widget reads, not just database opening.
    static func withReplacement(at databaseURL: URL, _ replace: () throws -> Void) throws {
        let access = try ClinicalDatabaseAccess(databaseURL: databaseURL, exclusive: true)
        defer { withExtendedLifetime(access) {} }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Void, any Error>?
        coordinator.coordinate(
            writingItemAt: databaseURL, options: .forReplacing, error: &coordinationError
        ) { _ in
            result = Result { try replace() }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ClinicalSharedDatabaseError.coordinationProducedNoDatabase }
        try result.get()
    }
}
