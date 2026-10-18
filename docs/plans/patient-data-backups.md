# Patient data backup implementation plan

Implement [the feature spec](../specs/patient-data-backups.md). This plan now has an implementation. See [validation evidence](../backup-validation.md) for completed checks and open release requirements.

## At a glance

| Decision | First version |
| --- | --- |
| Destination | Unshared `Clinical Backups` folder in Google Drive |
| Frequency | Once daily, with automatic retry |
| History | 30 days; always keep the latest successful copy |
| Coverage | All stored records and migration history |
| Setup UI | Settings sheet with backup status and Google controls; warning badge on its toolbar button |
| Recovery | Maintained restore code and an internal assisted harness |
| Verification | Separate `backup-test` and `backup-drive-check` targets; both required before release |
| Deferred | Full Backups screen, restore controls, recovery screen, full restore end-to-end suite |

## Existing code to preserve

| Area | Constraint |
| --- | --- |
| `ClinicalShared/ClinicalSharedDatabase.swift` | App Group database, persistent WAL, coordinated widget reads |
| `clinical-swift/persistence/Database.swift` | App owns migrations; disable debug erasure and sample seeding for recovery |
| `ClinicalApp.init()` | Replace the unconditional `try!` startup boundary so assisted recovery can run first |
| Calendar outboxes | Archive linkage and pending work; reconcile eligible records using the seven-day recovery cutoff |

Use the current source and `docs/persistence.md`, `docs/widgets.md`, `docs/calendar-sync.md`, and `docs/testing.md` as implementation references.

## Phase 1 — Connect Google Drive

- Enable the Drive API and configure an iOS OAuth client for Clinical's bundle ID and callback URL.
- Request `drive.file` plus only the identity scopes needed to bind the connected account. Clinical should manage files it creates, not the rest of the user's Drive.
- Use OAuth authorization code flow with PKCE through `ASWebAuthenticationSession`; use `URLSession` for token and Drive requests. No custom server or third-party package is planned.
- Keep tokens in Keychain and refresh access automatically. Bind pending work to a stable account identity; switching accounts must not upload retained patient data to a new account without explicit reassignment.
- Move OAuth publishing status out of **Testing** before routine use. Drive refresh tokens from an external Testing project expire after seven days. Complete the applicable basic consent/verification setup.
- Create an unshared, visible `Clinical Backups` folder. Persist its Drive ID; do not choose a folder by name alone. Keep separate subfolders for independent dataset IDs.

### Settings and backup status

| Area | First version |
| --- | --- |
| Schedule toolbar | A separate Settings group, then a creation group containing Unavailable Time and Add |
| Patients toolbar | A separate Settings group, then a creation group containing Add |
| Settings sheet | Backup state, last successful snapshot time, connected Google account, connect/reconnect controls, and any current problem |
| Warning badge | Apply SwiftUI `.badge()` to the Settings button's content when backup state needs attention; use one warning indicator, not a failure count |

Keep Settings immediately left of the creation group, with its own Liquid Glass background; do not merge it into the creation buttons' shared glass background. Keep creation buttons at the right edge for easy reach. Use the existing router/presentation rules for the sheet so it does not interrupt an active editor. Do not add a Settings tab or full backup history/restore screen.

Show running, waiting, successful, or needs attention. Success requires a confirmed Drive upload. Warn for missing authorization, full storage, failed backup work, or an overdue confirmed snapshot. Normal running/waiting activity does not itself need a warning badge. Explain the problem in Settings; opening the sheet does not clear it. Clear a failure only when resolved, and keep clinic editing available.

References: [Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), [native OAuth](https://developers.google.com/identity/protocols/oauth2/native-app), [token expiration](https://developers.google.com/identity/protocols/oauth2), [Apple's iOS 26 toolbar badge example](https://developer.apple.com/videos/play/wwdc2025/323/).

## Phase 2 — Create a safe snapshot

- Add a small backup module under `clinical-swift/backups/`, with separate database/file, Drive, and policy boundaries.
- Use the existing GRDB backup API on a worker actor. Include committed WAL changes; never copy only the live `.db` file.
- Close the destination as a standalone SQLite file with no required sidecars. Keep the live WAL configuration unchanged.
- Validate SQLite integrity and foreign keys. Include every table, terminal appointment state, Calendar outbox, and migration record.
- Produce a JSON manifest: format version, migration history, app version, snapshot/dataset IDs, capture time, byte count, and SHA-256 checksum.
- Store one validated pending snapshot and its manifest durably in protected Application Support. Keep upload state outside the clinical database so it survives database failure; do not use a purgeable cache.

Use HTTPS and Drive's encryption at rest. Keep patient fields out of filenames, metadata, and logs. No custom password or device-only encryption key is planned.

References: [GRDB backup API](https://github.com/groue/GRDB.swift/blob/v7.11.0/GRDB/Core/DatabaseReader.swift), [Drive privacy and encryption](https://support.google.com/drive/answer/10375054). Recheck the resolved package version during implementation.

## Phase 3 — Upload and retain backups

Each snapshot has two visible files: a dated `.db` and a matching `.json` manifest. Keep them unshared.

1. Pre-generate and persist both Drive file IDs before upload.
2. Upload the database first, then the manifest. List only complete pairs as restorable backups.
3. Confirm both files and matching metadata before recording success. If a response is lost, fetch those IDs and reconcile; a duplicate-ID conflict alone is not success.
4. Keep local pending files until success is durable. Retry the same IDs rather than creating duplicates.
5. After success, prune complete pairs older than 30 days within this dataset, except the latest successful pair. Deletion failures remain retryable maintenance work.

**Guardrails:** Paginate listings; leave unrelated files and other datasets alone. Never delete the last usable backup to make room. Ignore incomplete pairs during restore and clean them only when they are known abandoned app-owned work. Deleted folders or revoked access pause work and show a reconnect/setup warning.

Use a narrow Drive client for account/folder checks, file ID generation, upload confirmation, listing, download, and deletion. Large files can use resumable uploads; do not build a general sync system.

Reference: [Drive file creation and retry-safe IDs](https://developers.google.com/workspace/drive/api/guides/create-file).

## Phase 4 — Run daily without manual discipline

| Trigger or condition | Behavior |
| --- | --- |
| First eligible launch | Start the first backup after authorization |
| Launch/activation | Retry pending work; check whether 24 hours have elapsed since the last confirmed snapshot's capture time |
| Background opportunity | Run the same worker through `BGProcessingTaskRequest`, with networking required |
| Pending copy is already old when uploaded | Capture current data at the next eligible opportunity |
| Network/service failure | Bounded retry with backoff, then retry at a later opportunity |
| Full storage or revoked authorization | Preserve pending work, warn, and resume after resolution |
| Task expiration | Cancel, preserve validated work, release database access, and reschedule |

One coordinator serializes foreground and background work. Only the app writes backups; widgets remain readers. Do not hold database transactions during network calls. Respect GRDB suspension and close/release work when its execution window ends. Background work must not trigger authorization/Calendar prompts or sample seeding.

**Limit:** iOS does not guarantee a daily background wakeup. Foreground checks provide another opportunity. Retention also runs opportunistically; expired remote copies may remain longer while the app cannot run.

Reference: [Apple's scheduling limits](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate).

## Phase 5 — Restore code, with assisted invocation

Keep the restore implementation separate from future screens. The internal signed harness must run before normal database setup and support selecting an explicit backup, confirming replacement, and finalizing or rolling back recovery.

| Step | Required behavior |
| --- | --- |
| Download | Fetch the selected `.db` and manifest using the connected Google Account, or accept a pair downloaded from Drive into owned staging |
| Validate | Check format, checksum, size, integrity, foreign keys, dataset, and migration history; reject unsupported newer schemas |
| Prepare | Apply supported forward migrations on a working copy; disable debug erasure and seeding; apply the agreed Calendar recovery policy |
| Stop access | Pause backup/Calendar work, close app connections, and coordinate with existing widget readers |
| Replace | Journal the operation outside SQLite; preserve the old DB/WAL/SHM set; atomically install a standalone replacement on the same filesystem |
| Resume | Resolve an interrupted journal before normal startup; adopt the source dataset ID, clear stale pending uploads, reopen, and reload widgets |
| Finalize | Keep rollback evidence until the clinic owner verifies recovered data |

**Keep narrow:** No public restore deep link, silent restore, or separate script replacement algorithm. Exclude internal recovery/test invocation from ordinary distributed builds. Verify existing App Group reader/lock handling during implementation; file coordination alone does not close open widget pools.

### Calendar links and automatic retry

- Use the same iCloud account and clinic calendar. Do not add a calendar picker or change the temporary development calendar as part of this feature.
- Fix the recovery cutoff at the start of the day seven calendar days before recovery begins, using the app's calendar/time zone. Keep it unchanged if recovery resumes. Include restored items whose end is at or after the cutoff and all future items. This limits Calendar work only; restore all database records.
- For deletion tombstones without a source record, use the saved last-synced start to apply the cutoff; skip entries with an older or unknown date. Limit marker searches and event changes to the recovery window. Leave older Calendar events untouched, including those returned by direct ID lookup. Preserve excluded history in SQLite without queuing it for automatic recovery.
- Preserve link hints and pending deletion evidence. Treat restored EventKit IDs as hints; validate the event marker and target calendar before changing an event. Do not clear both outboxes as a blanket rule.
- Recover links by stable Clinical URL markers. The current one-day search can miss an event moved after the snapshot; design a wider, bounded search and retain the start time found during recovery. Consider server identifiers as additional hints, not the only identity.
- Reuse the existing search-and-replace path: if a successful search finds no event, create one when the restored item needs an event. Cancelled/deleted items only remove matching events. Do not add a grace-period timer or a new duplicate-reconciliation system; delayed iCloud visibility can leave a duplicate.
- Persist Calendar access, search, and write failures and retry on later app activations and available execution opportunities. A failure is not a successful empty search; never create a replacement in response to a permission or query error.
- Keep failures independent. Process work in batches, share/index Calendar queries where possible, and avoid a full-calendar search per appointment per retry. Support hundreds or thousands of records without individual operator review for temporary failures.
- After database replacement, queue every eligible restored Calendar link for reconciliation, including rows marked successfully synced. Do not replay excluded historical pending work on normal startup. Apply the snapshot values immediately when Calendar is available; do not wait for another Clinical edit. Preserve deletion tombstones. Failed items stay pending automatically; they must not block clinic edits or other Calendar work. If changes arrive during recovery, retain the latest desired operation and revision safeguards.
- Apply the same rules to appointments and unavailable-time blocks. Do not import Calendar content into the restored clinical database as an implicit side effect.

**Scope:** The snapshot is authoritative for its linked records within the recovery window. Overwrite newer Calendar values during reconciliation. Reuse existing replacement/deletion behavior and duplicate handling within the search results; define future search bounds during implementation without dropping future linked records. Do not add a full Calendar rollback engine. Events created only after the snapshot can remain because the restored database has no corresponding link or record. Leave unrelated events unchanged and document this limit.

Update [the recovery runbook](../patient-data-restore.md) with the actual harness invocation and tested checks.

## Phase 6 — Verify without a large end-to-end suite

### Local checks — `make backup-test`

Create a separate backup test bundle and shared scheme, selected by `make backup-test`. Exclude that bundle from the ordinary unit-test scheme so `make test` neither builds nor runs backup tests. Use production snapshot code, real temporary SQLite files, and fixed synthetic records. No account or network is needed.

1. Seed known patients, all appointment states, blocks, Calendar rows, and migration history. Include recent committed WAL writes.
2. Generate a real backup and record the expected contents.
3. Close/remove access to the source database and sidecars. Open only the backup read-only in an independent directory.
4. Check manifest checksum/size, `PRAGMA integrity_check`, and `PRAGMA foreign_key_check`.
5. Compare every stored row and field, ID, relationship, timestamp, and migration identifier. Counts alone are insufficient.

Add small corruption/checksum cases and focused tests for daily eligibility, retention, upload reconciliation, token expiry/account changes, and restore validation/journal rollback. Cover changed EventKit IDs, events moved beyond the old search window, snapshot values replacing newer Calendar values, creation after a successful empty search, and independent retries after access/write failure. Check both sides of the seven-day cutoff, future items, deletion tombstones, and that excluded pending work does not replay while all historical database records survive. Use injected time and fake Drive/Calendar clients for policy/network cases.

### Real Drive check — `make backup-drive-check`

Add a Make target that invokes a test harness using the production snapshot/upload/download code. Upload fixed synthetic data through real Drive, download that exact database/manifest pair, and repeat the contents, checksum, integrity, foreign-key, and schema checks. The retrieved bytes must not come from local upload staging. Return a nonzero exit code on failure, missing authorization, or unavailable required infrastructure; never report a skipped check as success.

Use an isolated test dataset and app-owned files. Do not read clinic records or apply retention to the clinic dataset. Keep credentials out of the repo and logs; authorize the test account once and refresh tokens automatically. Bound retries/timeouts and clean up only this run's files. Record results against the candidate source and configuration so unrelated earlier success cannot satisfy release checks.

During setup and changes to authorization, confirm OAuth publishing status is Production, exercise token refresh/reconnect, and verify the signed iOS harness on a physical device with the release configuration. Document the required device/account setup; routine release verification must run through the Make target without an operator marking a manual checklist complete.

### Required release steps

| Path | Required integration |
| --- | --- |
| `make release-testflight` | Run both checks for the candidate before upload; stop on failure |
| Direct `make upload-testflight` | Enforce the same checks in the shared upload path, including its build-number variant |
| Xcode Cloud | Run equivalent checks against the actual cloud checkout before distribution; configure credentials and required runner access before enabling this release path |

Create one shared release verification step that runs `make backup-test` and `make backup-drive-check` sequentially. Use it from each distribution path. Ensure `make -j` cannot upload while checks are still running. Match checked source/configuration to the archive being uploaded; reject an old archive whose source cannot be verified. Do not use local checks as evidence for a different remote branch or commit.

Keep both commands independently runnable. Update Make help, `docs/testing.md`, and the release/Xcode Cloud instructions during implementation. A missing account/device or Drive outage blocks release until the check can pass. No network check belongs in ordinary `make test` or `make build`.

**What this proves:** A complete, valid, standalone backup with expected records and a supported schema. Local tests should be stable because they need no account, network, or scheduled wakeup.

**What it does not prove:** Live database replacement or exact daily OS delivery. Keep focused restore safety checks and record any manual replacement checks separately. No recovery UI test or full restore end-to-end harness is required.

## Finish checklist

- [x] Run `make test`, `make backup-test`, `make backup-drive-check`, `make build`, and `git diff --check` during implementation.
- [x] Verify ordinary `make test` excludes backup tests, and every release/upload path requires both backup checks.
- [x] Record actual Drive download results for the current worktree in [validation evidence](../backup-validation.md).
- [x] Verify Calendar snapshot values, cutoff rules, changed IDs, and independent retries with focused tests. Live iCloud recovery is not claimed.
- [x] Verify App Group reader exclusion with a real read-only pool.
- [ ] Exercise actual BGProcessing expiration and suspension on a physical device. Cancellation and lifecycle handling are implemented; exact OS delivery is not proven.
- [x] Check Settings order, separate glass groups, status/date, and warning/normal badge states on both tabs. Check editor exclusion with a router test.
- [x] Add `docs/backups.md`; update the `AGENTS.md` map and affected persistence/widget notes.
- [x] Record OAuth setup, file format, warnings, and recovery invocation in the docs.
- [ ] Complete signed Release OAuth and reconnect on a physical iPhone. The owner asked to keep this check pending.
- [ ] Configure protected Xcode Cloud credentials and verify the cloud archive workflow before distribution.
- [ ] Mark the spec implemented after required checks pass. The spec remains pending.
