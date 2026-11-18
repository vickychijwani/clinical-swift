# Patient data backups

## Account and snapshot boundaries

Bind each dataset and pending upload to a stable Google account identity.
Reconnect must use that account. Missing, moved, or shared folders must stop
backups; do not redirect uploads or reuse an uncertain folder by name.

A backup must contain all committed data and open without the source database.
Validate it with its matching manifest. Keep patient fields out of remote
filenames and properties.

Recovery must survive database failure and app-container moves. Corrupt backup
state must stop backups without stopping clinic editing.

Interrupted uploads must resume without losing validated pending work or
credentials. Report success and remove pending local data only after confirming
the remote pair. Retention must preserve the newest usable pair and leave other
datasets and unrelated files untouched.

iOS does not guarantee daily background execution. Status must show confirmed
remote success, not merely that a task ran.

## Restore boundaries

Follow the [shared database rules](persistence.md#shared-database-access). Preserve
the original local data and enough recovery state to finish interrupted restore,
rollback, or finalization. Recovered data can be read before acceptance; rollback
must remain available until explicit finalization.

Recovery must not erase data or add samples. Future backups must use the recovered
dataset, not old pending uploads. See the [restore procedure](patient-data-restore.md)
and [Calendar recovery limits](calendar-sync.md#backup-recovery).

## Verification and release

Use an isolated Google account for live checks. Internal authorization must not
change the clinic's account binding.

Simulator setup:

1. Run `make backup-authorize` and complete Google sign-in.
2. Run `make backup-export-credentials`. It writes
   `~/.config/clinical-backups/check-credentials.json` with mode 600. Override the
   destination with `CLINICAL_BACKUP_CHECK_CREDENTIALS` if needed.
3. Run `make backup-drive-check CONFIGURATION=Release`.

Keep credentials outside the repository; revoke the grant when retiring the
runner. Keep Drive enabled and the Google project in External Production status:
Testing status can expire refresh tokens after seven days. See
[public Branding pages](../sites/README.md).

Distribution requires authorization evidence from a physical iPhone:

1. Build the signed app in Release with
   `CLINICAL_INTERNAL_CONDITIONS=INTERNAL_BACKUP_CHECK`.
2. Launch with `--backup-check-authorize`, complete Google sign-in, and check reconnect.
3. Export `Documents/backup-check-credentials.json` from the device container to
   the private runner path with mode 600.

Changing the client ID or callback scheme requires fresh device evidence.
Simulator checks cannot satisfy this requirement. Ordinary builds must not export
credentials or invoke recovery.

Run `make release-verify` for each candidate. Release backup checks must match the
source and archive being distributed. Record build settings in the project and
Makefile.

For Xcode Cloud setup, see [release checks](../ci_scripts/README.md). Local results
cannot authorize a different checkout.
