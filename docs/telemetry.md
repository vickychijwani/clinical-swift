# Telemetry and remote diagnostics

Clinical logs operational diagnostics, domain events, and MetricKit crash and
hang summaries to a local spool mirrored to `OSLog` and uploaded to Axiom.

## Boundaries and spool isolation

Keep telemetry spool files outside the database; Google Drive
[backups](backups.md) must never include telemetry files.

Keep `dev` (`clinical-dev`, Debug and Release Simulator) separate from `prod`
(`clinical-prod`, Release physical device). Tests and previews must never upload
remotely.

Because the widget runs in another process without spool locking, only the main
app mutates, seals, uploads, or evicts spool files or mints `device_id`; the
widget writes immutable per-run files atomically.

## Schema, privacy, and visibility

Use a closed flat schema (nested stacks serialized into `details`) so Axiom
ingestion stays well below its 256-field limit. Never record OAuth tokens,
refresh tokens, Keychain secrets, authorization codes, or `Authorization`
headers.

Records mirror to `OSLog` with `.public` formatting so clinic debugging data and
verbose SQL appear in Console and `sysdiagnose` on Release devices. Verbose
logging is off by default and auto-expires so Release devices do not stay
verbose.

## Silent failure

Telemetry failures must never badge the backup warning toolbar, interrupt clinic
workflows, or share `BackupCoordinator`'s background task.

## Axiom setup and token rotation

Configure these build settings on `clinical-swift`:

- `AXIOM_INGEST_DATASET`: `clinical-dev` for `Debug` and
  `Release[sdk=iphonesimulator*]`; `clinical-prod` for `Release`.
- `AXIOM_INGEST_URL`:
  `https://eu-central-1.aws.edge.axiom.co/v1/ingest/$(AXIOM_INGEST_DATASET)`
- `AXIOM_INGEST_TOKEN`: Write-only ingest token scoped to its target dataset.
  Leave empty to keep telemetry local-only.

For AI agent queries against EU-region Axiom organizations, connect the hosted
MCP endpoint `https://mcp.eu.axiom.co/mcp`.

To rotate a token, create a new ingest-only token in Axiom, update
`AXIOM_INGEST_TOKEN`, ship the new build, and revoke the old token after
adoption. Revoking a deployed token halts automatic uploads on `401`/`403` while
keeping spooled logs locally within the spool cap.
