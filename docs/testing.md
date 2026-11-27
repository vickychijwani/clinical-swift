# Testing

Use the [build and test execution rules](../AGENTS.md#build-and-test-execution)
and [Makefile](../Makefile) for commands and filters. See
[backup setup and release](backups.md#verification-and-release) for live checks
and credentials.

## Test boundaries

Write unit tests for core application logic; only write UI tests when unit tests
are not possible. Keep routine tests independent of Google accounts and network
access.

Package tests use public imports to enforce the same boundary as the app.
App-owned editors and platform setup belong in app tests.

Use `withDependencies` for construction and the complete operation under test so
production APIs do not acquire test-only parameters and results do not depend on
the host machine.

Prefer readable dates parsed with standard strategies (such as ISO-8601 strings)
over custom `DateComponents` fixture builders.

Do not link `DependenciesTestSupport` into hosted Xcode tests. Its second runtime
can make overrides change a different context from the one production code reads.

On Linux, run `swift package resolve` before `make data-test`. The Linux-only
OpenCombine dependency can be absent from a lockfile resolved on macOS.

## Local CI runner

Local jobs run with the Mac user's access. Allow only owner-triggered runs from
trusted code; review changes before allowing other contributors. Use a dedicated
CI simulator so tests cannot change development data.

The Mac must be awake, connected, and logged in. See the
[workflow](../.github/workflows/ios-tests.yml) for runner selection and setup.
If the Mac disconnects after selection, its job can remain queued until it returns.
