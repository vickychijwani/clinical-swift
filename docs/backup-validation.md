# Backup implementation validation

Initial checks ran on 11 October 2026 in the `0436/clinical-swift` worktree.
The correction checks below cover the later fixes. Release verification reruns
the checks for each candidate; this note cannot satisfy the release gate.

## Review corrections on 18 October 2026

Review issues 1–4 are fixed. Pending snapshots and restore journals resolve files
from the current containers, including when reading the previous saved format.
Calendar recovery keeps records without saved links or pending work out of
Calendar. Completed installation permits startup with active widget readers.
Backup cancellation also cancels token refresh and retains the saved credentials.

| Check | Result | Local evidence |
| --- | --- | --- |
| Ordinary unit tests, Debug | 192 tests passed | `build/backup-fixes/ordinary-unit.log` |
| Local backup tests, Release | 15 tests passed | `build/backup-fixes/backup-local.log` |
| Real Drive check, Release | Passed; token refresh and synthetic upload/download validation | `build/backup-fixes/backup-drive.log` |
| Internal Release build | Passed with `INTERNAL_RECOVERY` and `INTERNAL_BACKUP_CHECK` | `build/backup-fixes/internal-release.log` |
| Comment preservation and `git diff --check` | Passed | Local command output |

The regression tests move both the app and App Group roots while saved work
exists. Both the new and previous saved formats retain pending upload IDs, permit
installation, and restore the original rows and pending state on rollback.
An active read pool blocks replacement but permits a completed installation to
resume without changing data. Other tests check unlinked Calendar records and
cancellation of an in-flight token request, followed by a successful retry.

Checks used iPhone 17 Simulator with iOS 26.5. The ordinary test build reported
missing cached module files and the existing `PerceptionCore` dependency warning.
Strict `swift-format` lint reports the same three Google response-field naming
findings as the saved source baseline. SwiftLint is not installed.

Review issue 5 remains open. Physical-device OAuth, background execution, live
iCloud recovery, and Xcode Cloud validation remain pending. No clinic restore or
distribution was performed.

## Automated results

| Check | Result | Local evidence |
| --- | --- | --- |
| `make test` (Debug) | 192 tests in 32 suites passed | `build/ordinary-unit-final.log` |
| `make backup-test CONFIGURATION=Release` | 12 tests in 3 suites passed | `build/backup-local-final.log` |
| `make backup-drive-check CONFIGURATION=Release` | Real Drive round trip passed; 1 test, 10.656 seconds | `build/backup-drive-final.log` |
| `make build` (Debug) | Passed | `build/build-final.log` |
| Internal Release build, recovery and authorization conditions | Passed; app-only setting preserves widget conditions | `build/internal-build-final.log` |
| Plist/project parsing, shell/Python syntax, `git diff --check`, Stop hook | Passed | Local command output |

Tests used iPhone 17 Pro Simulator with iOS 26.5. The ordinary test build did not
include `clinical-swiftBackupTests`. Backup tests use a separate shared scheme.
SwiftLint is not installed on this host.

Local backup checks compare every table, row, field, ID, timestamp, relationship,
and migration identifier. They include committed WAL changes, then remove the
source and open a moved standalone snapshot read-only. Temporary paths include
spaces. Focused checks cover corruption/newer-schema rejection, account binding,
refresh, same-ID upload reconciliation, pagination, retention, seven-day Calendar
eligibility, changed event IDs, future search limits, and independent retries.
Restore checks include interrupted installation, rollback, and finalization.
A real read-only pool blocks the exclusive replacement lock until it closes.

The real Drive test forced token refresh, created an isolated UUID folder,
uploaded a synthetic database/manifest pair, retried the stored IDs, downloaded
that exact pair, removed upload staging, and validated the retrieved bytes and
all database values. Cleanup completed for that run's folder. Clinic data was not
used. Credentials remain outside the repository with mode 600.

## UI results

On iPhone 17 Simulator, Settings has a separate glass group immediately left of
the creation controls on Schedule and Patients. A missing-account warning remains
after opening and closing Settings. A temporary synthetic success state showed
success, the last snapshot date, and no badge on either tab. The fixture was
removed, and the normal missing-account warning was confirmed again.

Six local captures are in `build/backup-validation/`:

- `backupScheduleWarning.jpg`, `backupPatientsWarning.jpg`, `backupSettingsWarning.jpg`
- `backupScheduleSuccess.jpg`, `backupPatientsSuccess.jpg`, `backupSettingsSuccess.jpg`

The success captures prove display behavior only. The separate real Drive test
proves upload/download behavior. A router unit test verifies that Settings cannot
replace an active editor.

## Open requirements

- Signed Release OAuth and reconnect on a physical iPhone remain pending at the
  owner's request. Simulator credentials cannot pass the physical-device gate.
- Xcode Cloud needs protected check credentials and a successful archive workflow
  on its own checkout before cloud distribution is enabled.
- Actual BGProcessing expiration/suspension and live iCloud recovery were not
  exercised. Lifecycle cancellation is implemented; daily OS execution is not
  guaranteed.
- No clinic restore, full restore end-to-end test, archive upload, or distribution
  was performed. The spec remains pending.

`make release-verify` runs both Release suites sequentially, checks that the
candidate source did not change, then requires physical-device OAuth evidence.
All Make upload variants use this gate and verify archive/source receipts before
export. Missing credentials, failed Drive access, changed source/archive bytes,
or missing device evidence stop distribution. See [setup and release](backups.md)
and [assisted restore](patient-data-restore.md).
