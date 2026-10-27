# Assisted patient data restore

Use an internal signed build. Public recovery screens are deferred. Storage and
replacement rules are in [backups](backups.md); this procedure covers operator
steps.

## Before starting

- Stop clinic edits. Record the incident time, device, and app version.
- Keep Clinical installed. Preserve its App Group database and matching WAL/SHM
  files. Do not reset the device or launch a build that can erase changed schemas.
- Use the Google account connected for backups. For Calendar link recovery, use
  the same iCloud account and `Bitehaus Debug` calendar.
- Keep remote backups and downloaded originals unchanged until acceptance.

## Select and stage a pair

In Google Drive, open `Clinical Backups`, then the intended dataset UUID folder.
Choose a capture before the incident and download its matching `.db` and `.json`
files. Ignore incomplete pairs. Record dataset ID, snapshot ID, capture time,
checksum, size, and schema history without including patient fields in reports.

Copy the pair into an owned staging directory in the app container as `snapshot.db`
and `snapshot.json`. Keep the manifest's original bytes. Confirm its dataset ID;
`--restore-dataset` must name the intended dataset, not merely repeat an unchecked ID.

Optional independent Mac checks:

```sh
shasum -a 256 '/absolute/path/to/snapshot.db'
wc -c < '/absolute/path/to/snapshot.db'
sqlite3 -readonly '/absolute/path/to/snapshot.db' 'PRAGMA integrity_check; PRAGMA foreign_key_check;'
sqlite3 -readonly '/absolute/path/to/snapshot.db' 'SELECT identifier FROM grdb_migrations ORDER BY rowid;'
```

Integrity must return `ok`, foreign keys must return no rows, and checksum/size must
match the manifest. Counts alone do not prove that the right records were saved.
Do not install an invalid or unsupported backup.

## Build and invoke

Use a signed **Release** app build with
`CLINICAL_INTERNAL_CONDITIONS=INTERNAL_RECOVERY`. Keep the ordinary bundle ID and
App Group entitlements; verify the developer team and installed-data access. Do
not distribute this build. Ordinary builds have no restore command or public URL.

Terminate the app before each invocation. Set the selected launch arguments in
Xcode's Run scheme. Transfer staging files through Xcode's device container support.
Paths below refer to the current on-device container, not a Mac path; installation
can change that container path.

| Action | Launch arguments |
| --- | --- |
| Install chosen pair | `--restore-import /absolute/on-device/staging --restore-dataset <dataset-UUID> --confirm-restore` |
| Retry interrupted installation | No import argument; startup resolves the existing journal |
| Restore original local file set | `--restore-rollback` |
| Accept recovered data or completed rollback | `--restore-finalize --confirm-restore` |

For Simulator, use
`xcrun simctl launch <simulator-id> in.bitehaus.clinical <arguments>`. This does not
verify recovery on the physical clinic device.

Import validates and migrates a working copy with debug erasure and seeding
disabled. If coordination fails, keep the journal and retry. Do not manually move
files around an unresolved journal. Once installed, the app can reopen and
reconcile Calendar, but backups remain paused until finalization.

Rollback restores the original local file set. It cannot undo Calendar changes
already delivered. Read the [Calendar recovery limits](calendar-sync.md#backup-recovery)
before acceptance.

## Verify and accept

- Check known patient details, upcoming and historical appointments, blocks, and
  the accepted loss window. Confirm editing and widget reads on the target device.
- Check Calendar in the original account. Snapshot values replace linked values
  within the recovery window. Older events remain unchanged; duplicates and events
  created after the capture can remain.
- Finalize only after the clinic owner accepts the data. Return to the ordinary
  build. Check relaunch, a new edit, and the next confirmed Drive backup.
- Remove unnecessary staging exports and unreferenced pending files after acceptance.
  Keep reports free of patient fields.
