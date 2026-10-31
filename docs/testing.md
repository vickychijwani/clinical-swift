# Testing

## Entry points

- `make data-test`: package model and persistence tests without an app host or
  simulator. Requires Swift 6.4 or later.
- `make test`: package and app unit tests. UI and backup tests stay outside its
  build graph so routine checks need neither extra test hosts nor account setup.
- `make ui-test`: UI tests only.
- `make backup-test`: local backup tests without network access.
- `make backup-drive-check`: real Drive round trip with an isolated test account.

See [backup setup and release](backups.md#verification-and-release) for credentials
and the release gate. The [Makefile](../Makefile) owns command options and schemes.

On Linux, run `swift package resolve` before `make data-test`. The dependency
graph includes OpenCombine only on Linux, so a lockfile resolved on macOS can
omit it. CI resolves first, then checks shared versions and revisions against the
app lockfile before it runs tests with automatic resolution disabled.

## Local CI runner

UI CI uses the `clinical-ios` ARM64 runner on the local Mac when it is online
and idle. Otherwise it uses GitHub's macOS runner. Its local work directory
is `~/ci/clinical-swift/work`; the runner keeps the same checkout path across jobs.
Build state stays in `~/ci/clinical-swift/cache`, outside checkout cleanup, with a
separate cache for each Xcode build. UI tests run in sequence on `CI Simulator 1`
(iPhone 17, iOS 26.5). Keep this simulator for CI so tests cannot change a
development simulator's data.

The runner is a login service. The Mac must be awake, connected, and logged in.
To check or restart it:

```sh
cd ~/ci/clinical-swift/runner
./svc.sh status
./svc.sh stop
./svc.sh start
```

To replace the CI simulator after a runtime removal, create one with the same
name and update the workflow destination if the runtime changes:

```sh
xcrun simctl create 'CI Simulator 1' \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17 \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
xcrun simctl bootstatus 'CI Simulator 1' -b
```

Local UI jobs accept only non-draft PRs opened by the repository owner from
this repository, with runs triggered by that owner. Review changes before
allowing other contributors to use this runner: jobs run with the local user's
access. Other non-draft PRs use GitHub's macOS runner for UI tests.

The routing check needs the repository Actions secret `RUNNER_STATUS_TOKEN`:
use a fine-grained token limited to this repository with Administration read
permission. Missing or expired credentials and failed status checks select
GitHub's macOS runner. The check is a snapshot: if the Mac disconnects after
selection, GitHub can still queue the job until the runner returns.

App unit tests, local backup tests, Linux tests, and architecture
validation use GitHub-hosted runners.

## Test boundaries

Package tests use public imports to check the same API boundary as the app. Tests
for app-owned editors and platform setup stay in the app test bundle.

Override registered dependencies with `withDependencies` around construction and
the complete operation under test. A live dependency makes tests depend on the
machine and can produce a dependency-access test failure.

Do not link `DependenciesTestSupport` into the hosted Xcode test bundle. It loads a
second dependency runtime, so test overrides can change a different context from
the one production code reads.
