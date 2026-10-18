# Assisted patient data restore

## Scope

Use the maintained restore service through an internal signed build. Public
recovery screens are deferred. Local tests exercise validation, journal resume,
rollback, and Calendar eligibility. They do not prove a recovery on the clinic's
physical device. See [backup storage and account rules](backups.md).

## Before starting

- Stop clinic edits. Record incident time, device, and app version.
- Keep Clinical installed. Preserve its App Group database and matching WAL/SHM
  files. Do not reset the device or launch a build that can erase changed schemas.
- Use the Google account connected for backups. Use the same iCloud account and
  `Bitehaus Debug` calendar for Calendar link recovery.
- Keep existing Drive backups and downloaded originals unchanged until acceptance.

## Select a pair

In Google Drive, open `Clinical Backups`, then the required dataset UUID folder.
Choose a capture before the incident. Download the matching dated `.db` and `.json`
files. Ignore incomplete pairs. Record dataset ID, snapshot ID, capture time,
checksum, size, and schema history. Keep patient fields out of reports and logs.

The first internal harness accepts downloaded files. It does not have a Drive
browser. Copy the chosen pair into an owned app-container staging directory and
name the files `snapshot.db` and `snapshot.json`. The manifest must retain its
original bytes. Confirm that its dataset ID is the intended clinic dataset before
proceeding. The service checks that exact manifest against the database bytes;
the required `--restore-dataset` argument checks the intended dataset explicitly.

Optional independent Mac checks:

```sh
shasum -a 256 '/absolute/path/to/snapshot.db'
wc -c < '/absolute/path/to/snapshot.db'
sqlite3 -readonly '/absolute/path/to/snapshot.db' 'PRAGMA integrity_check; PRAGMA foreign_key_check;'
sqlite3 -readonly '/absolute/path/to/snapshot.db' 'SELECT identifier FROM grdb_migrations ORDER BY rowid;'
```

Integrity must return `ok`, foreign keys must return no rows, and checksum/size
must match the manifest. Counts alone do not prove the right records were saved.
Do not install an invalid or unsupported backup.

## Build and invoke

Use a signed **Release** internal build of the app target. Set
`CLINICAL_INTERNAL_CONDITIONS=INTERNAL_RECOVERY` for this build only. Keep the
ordinary bundle ID and App Group entitlements, and verify the developer team and
installed-data access. Do not distribute this build. Ordinary builds have no
restore command or public restore URL.

Terminate the app before each invocation. In Xcode's Run scheme, set the launch
arguments to the selected action below. Paths refer to the app's on-device
container, not to a Mac path. Transfer staging files through Xcode's device
container support. Use the current container path after installation; it can
change.

| Action | Launch arguments |
| --- | --- |
| Install chosen pair | `--restore-import /absolute/on-device/staging --restore-dataset <dataset-UUID> --confirm-restore` |
| Retry interrupted installation | No import argument; startup resolves the existing journal |
| Restore original local file set | `--restore-rollback` |
| Accept recovered data or completed rollback | `--restore-finalize --confirm-restore` |

For Simulator, the same signed-build logic can be exercised with
`xcrun simctl launch <simulator-id> in.bitehaus.clinical <arguments>`. Simulator
invocation does not prove physical-device signing or OAuth.

Import validates format, checksum, size, integrity, foreign keys, and supported
migration history. It applies forward migrations to a working copy, with debug
erasure and seeding disabled. It fixes the local seven-day Calendar cutoff and
queues eligible links, including previously successful rows. All historical
records and excluded link evidence remain in SQLite. Records without a saved
Calendar link or pending entry stay outside Calendar recovery.

Before replacement, an exclusive file lock excludes app/widget pools. If a widget
still holds a reader, startup stops safely. Retry after the reader exits. The
journal preserves the original DB/WAL/SHM set before a same-filesystem atomic
rename installs the standalone replacement. It adopts the restored dataset and
clears old pending-upload references. Do not manually rearrange files around an
unresolved journal.

An installed journal allows the app to reopen and reconcile Calendar. Backups
remain paused until finalization. Rollback evidence stays in protected Application
Support. Rollback restores the original local file set; it cannot undo Calendar
changes already delivered after installation.

## Verify and accept

- Check known patient details, upcoming/historical appointments, blocks, and the
  accepted loss window. Confirm editing and widget reads.
- Check Calendar in the original iCloud account. Snapshot values replace linked
  values within the fixed recovery window. Failed items retry independently.
  Older events remain unchanged. Delayed iCloud visibility can leave duplicates;
  events created only after capture can remain because no restored link identifies
  them. See [Calendar recovery limits](calendar-sync.md#backup-recovery).
- Finalize only after the clinic owner accepts the data. Return to the ordinary
  build. Check relaunch, a new edit, and the next confirmed Drive backup.
- Remove unnecessary staging exports and unreferenced pending files after
  acceptance. Keep shared reports free of patient fields.

## Evidence

The separate backup suite uses temporary synthetic databases. It validates a
standalone WAL-inclusive snapshot after removal of the source, all stored rows
and fields, corruption rejection, migration rejection, reader exclusion, journal
resume, rollback, and Calendar cutoff eligibility. The real Drive suite must pass
for the candidate before distribution. Record physical-device recovery checks
separately; no full restore end-to-end test is claimed.
