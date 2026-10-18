# Patient data backups

## Data and account boundaries

Clinical uses Google Drive `drive.file`, `openid`, and `email` access. Native OAuth
uses PKCE and a system authentication session. Tokens stay in Keychain with
`AfterFirstUnlockThisDeviceOnly` protection. The stable Google account ID binds
both the dataset and pending uploads. Reconnect must use that account. An email
address alone is not an account identity.

The iOS OAuth client belongs to Google project `clinical-79c20`. Its identifiers
are public app configuration in `Info.plist`. The owner confirmed External
Production status on 11 October 2026. Keep the Drive API enabled. Testing status
can expire refresh tokens after seven days. The public Branding pages are listed
in [the Sites record](../sites/README.md).

The app stores an unshared `Clinical Backups` folder ID, then a dataset subfolder
ID. It does not select folders by name. A missing or shared folder stops work. A dataset folder moved out of its
recorded root also stops work. Restore access and reconnect; do not silently upload to another account.

## Files and durable state

Each capture has a UUID and two files: a dated `.db` and matching `.json`.
Filenames and Drive properties contain no patient fields. The manifest records
format version 1, dataset and snapshot IDs, whole-second UTC capture time, app
version, ordered migration IDs, byte count, and SHA-256 of the database bytes.

The SQLite backup API captures committed WAL changes consistently. The closed
snapshot uses DELETE journal mode and opens read-only without sidecars. Integrity,
foreign keys, checksum, size, and supported migration prefix must all pass.

Application Support `ClinicalBackups` holds protected state and the pending pair.
These files are excluded from OS backup. State is outside SQLite, so database
failure does not remove recovery metadata. File APIs and SQLite use decoded file
paths, including spaces in Application Support. A corrupt state file stops backup work;
keep it for assisted repair. It must not stop clinic editing.

Pending state stores the manifest and remote file IDs. Resolve its local pair from
the snapshot ID under the current Application Support directory. Restore journals
store a recovery ID and resolve the live database from the current App Group.
Do not retain absolute container paths: an app update can move those containers.
Older state and journals remain readable; their saved IDs locate the files under
the current roots.

Persist both generated Drive IDs before upload. Upload the database, then the
manifest. Fetch each ID and compare its parent, privacy, size, SHA-256, and app
properties before success. A duplicate-ID conflict is only a reason to fetch and
check. Persist success before removing local pending bytes. Listings paginate and
expose only complete pairs from this dataset.

Keep complete pairs for 30 days. Always keep the newest remote pair and the local
confirmed success. Persist unfinished deletions and recheck ownership before
retrying. Never delete unrelated files, another dataset, or the only usable pair.
An orphan from interrupted folder creation can remain; it is safer to leave an
unreferenced folder than select it by name or delete uncertain data.

## Scheduling and status

A single coordinator runs on authorization, launch, activation, and network-enabled
BGProcessing opportunities. Eligibility uses 24 hours since the last confirmed
capture. Pending work keeps its capture time and IDs. If it is old after upload,
the next opportunity can capture again. Failed opportunities use exponential
backoff from one minute to one hour. Manual retry clears the delay.

Cancellation retains validated pending files. Snapshot copying checks cancellation
between SQLite backup steps. Token refresh runs in the backup task, so cancellation
also stops the token request and keeps the saved credentials. Background work
resumes the database, waits for work to end, then suspends it if the app is still
in the background. It does not request Google or Calendar permission. iOS does not
guarantee daily background execution.

Settings shows running, waiting, success, or needs attention. Success means remote
confirmation. Missing authorization, a current error, or a confirmed/pending
snapshot at least 48 hours old keeps the native warning badge visible. Opening
Settings does not clear it. The router rejects Settings while an editor is active.

## Restore boundaries

See [assisted restore](patient-data-restore.md) for the internal invocation. Restore
runs before live pools open. A shared process lock covers the full lifetime of app
and widget pools. An exclusive restore lock fails while a reader still owns the
old database. Retry after the extension releases it; file coordination alone does
not close a pool. An installed journal needs no exclusive lock for normal startup,
because no database files change in that phase.

The journal and original DB/WAL/SHM set remain outside the replaced database.
Replacement uses a same-filesystem atomic rename. Interrupted installation resumes
before normal startup. Rollback and finalization save their intent before changing
files, so startup can finish either action after termination. Rollback remains
available until explicit finalization.
Recovery disables sample seeding and destructive debug schema repair. The restored
dataset is adopted and old pending upload references are cleared. Unreferenced
pending files can be removed after recovery is accepted.

Calendar recovery restores every database record. Its fixed seven-day cutoff only
limits Calendar work. See [Calendar recovery](calendar-sync.md#backup-recovery).

## Verification and release

`make backup-test` uses a separate bundle and no account or network. `make test`
does not build that bundle. The fixture includes every table/field, all appointment
states, nil values, links, deletion tombstones, and committed WAL writes. The test
removes the source and opens the independent snapshot read-only.

`make backup-drive-check` requires an isolated account credential file outside the
repository. It forces token refresh, uploads synthetic data with production code,
reconciles the same IDs, downloads the exact remote pair, removes upload staging,
and compares every row and field. Missing credentials and infrastructure failures
are failures, not skips. Cleanup deletes only the UUID folder created by that run.

Set up credentials once with `make backup-authorize`. Complete Google sign-in in
Simulator, then run `make backup-export-credentials`. The default destination is
`~/.config/clinical-backups/check-credentials.json`, mode 600. Keep this file private.
Override its path with `CLINICAL_BACKUP_CHECK_CREDENTIALS`. Revoke this grant when
retiring the runner. Ordinary builds cannot export credentials or invoke recovery.

The shared `make release-verify` runs both checks sequentially in Release with testability enabled for the host module. All Make
upload paths call it from inside the upload recipe, including with `make -j`.
Archives record source/configuration and archive-byte hashes. A changed source or
old archive without a matching receipt must be rebuilt. Keep build settings in the
checked project/Makefile; do not upload an archive built with unrecorded overrides.

Xcode Cloud archive actions run the same gate before building. Configure the
protected `CLINICAL_BACKUP_CHECK_CREDENTIALS_BASE64` secret with the isolated
credential JSON, plus a usable simulator and network access. The post-build hook
rejects a changed checkout. Distribution is blocked without this setup. A local
result cannot verify a different cloud checkout.

The release gate also requires physical-device authorization evidence for the
configured client ID and callback scheme. Build the signed app in Release with
`CLINICAL_INTERNAL_CONDITIONS=INTERNAL_BACKUP_CHECK`, launch with `--backup-check-authorize`, and complete native
Google sign-in. Export `Documents/backup-check-credentials.json` from its device
container to the private runner path, with mode 600. The internal build records
whether authorization ran on a physical device in Release. This is generated
from the actual native session; a manually marked checklist cannot satisfy it.
Changing the client ID or callback scheme requires fresh device evidence.
The custom setting adds conditions only to the app target, so widget and package
conditions remain intact. Do not override compilation conditions for every target.

Check reconnect on that device as well. Routine Drive checks force token refresh.
Simulator credentials can run the independent Drive check, but cannot allow
release distribution. Simulator checks do not prove physical-device signing or
exact OS wakeup timing. The physical-device check remains pending at the owner's
request; keep the spec pending until it passes.
