# Assisted patient data restore

Use a signed internal build; public recovery is deferred. See [backups](backups.md)
for restore boundaries.

## Before starting

- Stop clinic edits. Record the incident time, device, and app version.
- Keep Clinical installed and preserve its App Group database and WAL/SHM files.
  Do not reset the device or launch a build that can erase data after schema changes.
- Use the Google account connected for backups. For Calendar link recovery, use
  the same iCloud account and `Bitehaus Debug` calendar.
- Keep remote backups and downloaded originals unchanged until acceptance.

## Select and stage a pair

In Google Drive, open `Clinical Backups` and the intended dataset UUID folder.
Download a matching `.db` and `.json` pair captured before the incident. Record
dataset ID, snapshot ID, capture time, checksum, size, and schema history. Keep
patient fields out of reports.

Stage the pair in the app container as `snapshot.db` and `snapshot.json`. Keep the
manifest bytes unchanged. Independently confirm the dataset ID before using it
with `--restore-dataset`.

Optional independent Mac checks:

```sh
shasum -a 256 '/absolute/path/to/snapshot.db'
wc -c < '/absolute/path/to/snapshot.db'
sqlite3 -readonly '/absolute/path/to/snapshot.db' 'PRAGMA integrity_check; PRAGMA foreign_key_check;'
sqlite3 -readonly '/absolute/path/to/snapshot.db' 'SELECT identifier FROM grdb_migrations ORDER BY rowid;'
```

Integrity must return `ok`, foreign keys no rows, and checksum/size must match the
manifest. Counts do not prove record identity. Reject invalid or unsupported backups.

## Build and invoke

Use a signed **Release** build with
`CLINICAL_INTERNAL_CONDITIONS=INTERNAL_RECOVERY`. Keep the ordinary bundle ID and
App Group entitlements. Verify the developer team and installed-data access. Do
not distribute this build.

Terminate the app before each invocation. Transfer files with Xcode's device
container support and set launch arguments in its Run scheme. Use current
on-device paths; installation can change the container path.

| Action | Launch arguments |
| --- | --- |
| Install chosen pair | `--restore-import /absolute/on-device/staging --restore-dataset <dataset-UUID> --confirm-restore` |
| Retry interrupted installation | No import argument; startup resolves the existing journal |
| Restore original local file set | `--restore-rollback` |
| Accept recovered data or completed rollback | `--restore-finalize --confirm-restore` |

For Simulator, use
`xcrun simctl launch <simulator-id> in.bitehaus.clinical <arguments>`. This does not
verify recovery on the physical clinic device.

If installation is interrupted or coordination fails, keep recovery files and
retry. Do not move files around an unresolved journal. The app can reopen and
reconcile Calendar after installation; backups remain paused until finalization.

Rollback restores original local files. Read the
[Calendar recovery limits](calendar-sync.md#backup-recovery) before acceptance.

## Verify and accept

- Check known patient details, upcoming and historical appointments, blocks, and
  the accepted loss window. Confirm editing and widget reads on the target device.
- Check Calendar in the original account against those recovery limits.
- Finalize only after the clinic owner accepts the data. Return to the ordinary
  build. Check relaunch, a new edit, and the next confirmed Drive backup.
- Remove unnecessary staging exports and unreferenced pending files after acceptance.
