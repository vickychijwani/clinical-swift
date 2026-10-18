# Testing

This document captures testing rules that are easy to miss under strict Swift concurrency.

## Test Commands

- `make test` uses the shared unit-test scheme and must not build or run the UI-test target. Parallel Xcode test runners are disabled for this command so it can use the selected simulator directly instead of creating a simulator clone.
- `make ui-test` uses the separate shared UI-test scheme. Keep unit and UI targets in their respective schemes so selecting one kind of test does not build the other bundle.

## Backup checks

- `make backup-test` builds only the separate backup bundle through `clinical-swift-Backups`. It skips `BackupDriveTests` and needs no network.
- `make backup-drive-check` selects only `BackupDriveTests`. Missing credentials fail the command. See [backup setup and release rules](backups.md).
- `make release-verify` runs both in sequence in Release. Upload recipes enforce it before export; do not replace the gate with an earlier result from a different source tree.
- Ordinary `make test` keeps backup tests out of its build graph.
- Set `CLINICAL_INTERNAL_CONDITIONS=INTERNAL_BACKUP_CHECK` for the backup scheme to
  include internal authorization tests. They use synthetic OAuth responses and
  separate Keychain entries. They check credential export, account isolation,
  cancellation, and export failures without a Google session.

## Async Database Access

- In an `async` test, calls to `DatabaseWriter.read` and `DatabaseWriter.write` resolve to their asynchronous overloads. Always write `try await database.read { ... }` and `try await database.write { ... }`.
- This applies even when the database is an in-memory `DatabaseQueue` and the closure itself contains no suspension point. Overload selection follows the surrounding async context, not whether the closure appears synchronous.
- Keep purely synchronous database tests synchronous when practical. When a test must be async, audit every database read and write in that test for the required `await`.

## Test Dependencies

- Override registered ambient values with `withDependencies` around model construction or the complete operation under test. Keep narrower scopes when a test needs a value with specific semantics, such as a fixed time zone.
- Do not let tests fall through to live implementations of registered ambient values. Besides making tests environment-dependent, `swift-dependencies` reports live dependency access as a test issue.
- Do not link `DependenciesTestSupport` into this Xcode test bundle. Its static dependency runtime duplicates the package framework loaded by the host app, causing test overrides to mutate a different `DependencyValues` context than production models read.
