# Telemetry and remote diagnostics

Clinical logs operational diagnostics, domain events, and MetricKit crash and
hang summaries to a local spool mirrored to `OSLog` and uploaded to Axiom.

## Boundaries and spool isolation

Follow [architecture boundaries](architecture.md) so shared telemetry types run
on Linux and widget telemetry stays free of persistence and app UI.

Keep spool files outside `SQLiteData.db` in `<AppGroup>/Telemetry/<env>/`. Google
Drive [backups](backups.md) never include telemetry files.

Keep `dev` (`clinical-dev`, Debug and Release Simulator) separate from `prod`
(`clinical-prod`, Release physical device). Unit tests, UI tests, and previews
disable remote uploads.

Only the main app appends, seals, uploads, evicts, deletes spool files, or mints
`device_id`. Because the widget runs in another process without spool locking, it
writes immutable per-run files atomically. Keep each environment within a 20 MB
cap, evicting debug-only logs before normal and error records.

## Schema, privacy, and visibility

Use a closed flat schema (nested stacks serialized into `details`) so Axiom
ingestion stays well below its 256-field limit. Never record OAuth tokens,
refresh tokens, Keychain secrets, authorization codes, or `Authorization`
headers.

Every record mirrors to `OSLog` (`in.bitehaus.clinical`) with `.public`
formatting, so clinic debugging data and verbose SQL statements appear in Console
and `sysdiagnose` on Release devices. Verbose logging is off by default in
Settings -> Diagnostics and auto-expires after 24 hours so Release devices do not
stay verbose.

## Silent failure

Telemetry failures never badge the backup warning toolbar, interrupt clinic
workflows, or share `BackupCoordinator`'s background task. Upload errors appear
only in Settings -> Diagnostics.

## Axiom setup and token rotation

Configure these build settings on `clinical-swift`:

- `AXIOM_INGEST_DATASET`: `clinical-dev` for `Debug` and
  `Release[sdk=iphonesimulator*]`; `clinical-prod` for `Release`.
- `AXIOM_INGEST_URL`:
  `https://eu-central-1.aws.edge.axiom.co/v1/ingest/$(AXIOM_INGEST_DATASET)`
  (legacy dataset ingest URLs also work).
- `AXIOM_INGEST_TOKEN`: Write-only ingest token scoped to its target dataset.
  Leave empty to keep telemetry local-only.

For AI agent queries against EU-region Axiom organizations, connect the hosted MCP
endpoint `https://mcp.eu.axiom.co/mcp`.

To rotate a token, create a new ingest-only token in Axiom, update
`AXIOM_INGEST_TOKEN`, ship the new build, and revoke the old token after adoption.
Revoking a deployed token halts automatic uploads on `401`/`403`, keeps spooled
logs within the 20 MB cap, and reports the error in Settings -> Diagnostics.
