# Testing

## Entry points

- `make data-test`: package model and persistence tests without an app host or
  simulator. Requires Swift 6.2 or later.
- `make test`: package and app unit tests. UI and backup tests stay outside its
  build graph so routine checks need neither extra test hosts nor account setup.
- `make ui-test`: UI tests only.
- `make backup-test`: local backup tests without network access.
- `make backup-drive-check`: real Drive round trip with an isolated test account.

See [backup setup and release](backups.md#verification-and-release) for credentials
and the release gate. The [Makefile](../Makefile) owns command options and schemes.

## Test boundaries

Package tests use public imports to check the same API boundary as the app. Tests
for app-owned editors and platform setup stay in the app test bundle.

Override registered dependencies with `withDependencies` around construction and
the complete operation under test. A live dependency makes tests depend on the
machine and can produce a dependency-access test failure.

Do not link `DependenciesTestSupport` into the hosted Xcode test bundle. It loads a
second dependency runtime, so test overrides can change a different context from
the one production code reads.
