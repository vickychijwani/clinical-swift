# Patient data backups

## Account and snapshot boundaries

Bind the dataset and pending uploads to the stable Google account ID, not an email
address. Reconnect must use that account. Address Drive folders by saved IDs;
missing, moved, or shared folders must stop backup work rather than redirect it.
An uncertain orphan is safer to leave than to delete or reuse by name.

Use the SQLite backup API to capture committed WAL data. A copied database file
alone can omit committed edits. The result must be a validated standalone database
with its matching manifest. Keep patient fields out of remote filenames and
properties.

Keep recovery state outside SQLite so a database failure does not remove it.
Resolve saved file IDs under current container roots; app updates can move those
roots. Corrupt backup state must stop backup work without stopping clinic editing.

Persist remote file IDs before upload so retries reconcile the same files after
interruption. Confirm the remote pair before reporting success or deleting local
pending bytes. Retention must preserve the newest usable pair and must never
remove another dataset or unrelated files. Cancellation retains validated pending
work and saved credentials. iOS background opportunities do not guarantee a daily
backup, so status must reflect confirmed remote success rather than task execution.

## Restore boundaries

Restore runs before live app pools open and follows the shared
[database access rules](persistence.md#shared-database-access). Keep the journal and
original database/WAL/SHM set outside the replaced database. Save rollback or
finalization intent before changing files so startup can finish interrupted work.
An installed journal permits ordinary reads; rollback remains available until
explicit finalization.

Recovered data must not pass through debug erasure or sample seeding. Adopt its
dataset and clear old pending-upload references. See the
[restore procedure](patient-data-restore.md) for invocation and acceptance, and
[Calendar recovery](calendar-sync.md#backup-recovery) for external side effects.

## Verification and release

Use an isolated Google account for live checks. The internal authorization flow
uses separate credentials and must not change the clinic account binding.

For simulator setup:

1. Run `make backup-authorize` and complete Google sign-in.
2. Run `make backup-export-credentials`. It writes
   `~/.config/clinical-backups/check-credentials.json` with mode 600. Override the
   destination with `CLINICAL_BACKUP_CHECK_CREDENTIALS` if needed.
3. Run `make backup-drive-check CONFIGURATION=Release` to check the live round trip.

Keep credentials outside the repository and revoke the grant when retiring the
runner. Keep the Google project in External Production status with Drive enabled;
Testing status can expire refresh tokens after seven days. Public client settings
are in `Info.plist`; public Branding pages are in [the Sites record](../sites/README.md).

Distribution also requires native authorization evidence from a physical iPhone:

1. Build the signed app in Release with
   `CLINICAL_INTERNAL_CONDITIONS=INTERNAL_BACKUP_CHECK`.
2. Launch with `--backup-check-authorize`, complete Google sign-in, and check reconnect.
3. Export `Documents/backup-check-credentials.json` from the device container to
   the private runner path with mode 600.

The internal flow records physical-device evidence for the client ID and callback
scheme. Changing either requires fresh evidence. Simulator credentials can run
the Drive check but cannot satisfy this release requirement. Ordinary builds cannot
export credentials or invoke recovery.

Run `make release-verify` for the candidate. It runs local and live backup checks in
Release and checks device evidence. Upload paths enforce the gate against the same
source and archive; an old result or changed archive cannot stand in for it. Keep
build settings in the checked project and Makefile, not unrecorded overrides.

For Xcode Cloud, configure the protected
`CLINICAL_BACKUP_CHECK_CREDENTIALS_BASE64` secret with the isolated credential JSON,
plus a usable simulator and network access. Cloud archives run the same gate on
their own checkout. See [testing](testing.md) for routine test entry points.
