# Telemetry and Remote Diagnostics

Clinical records operational logs, structured domain events, and Apple MetricKit crash and hang summaries in one chronological stream.

## Architecture and Boundaries

- `ClinicalModels` defines `TelemetryRecord` and `TelemetryClient: TestDependencyKey` with only `Foundation` and `Dependencies` so package tests stay Linux-compatible.
- `ClinicalShared` owns `TelemetrySpool` and `TelemetrySettingsStore` for both the app and widget targets without persistence or UI imports.
- `clinical-swift/telemetry/` owns the live `DependencyKey`, `LogBatchEncoder` (`AxiomFlatJSONEncoder`), system `zlib` gzip compression, `TelemetryCoordinator`, and `MetricKitCollector`.

## Cross-Process Spool and Isolation

- Spool files live in `<AppGroup>/Telemetry/<env>/` (`dev` or `prod`), outside `SQLiteData.db`. Google Drive patient backups never include telemetry files.
- Debug builds and Release Simulator builds route to `dev` (`clinical-dev`). Release physical-device builds route to `prod` (`clinical-prod`). Unit tests, UI tests (`--ui-testing-*`), and SwiftUI previews disable remote uploads.
- Only the main app appends to `active-app.ndjson`, seals segments, uploads, evicts, and deletes files.
- The widget extension collects records in memory during each `getTimeline` or `getSnapshot` call and writes one immutable file (`seg-<unixMillis>-widget-<uuid>.ndjson`) with atomic file replacement. Only the main app mints `device_id`.
- On seal (at 256 KB or before flush), the main app drops any incomplete trailing line without a newline and removes invalid JSON lines so a crash never poisons an upload batch.
- Each environment enforces a 20 MB spool cap sorted strictly by filename timestamp. Debug-only segments (`-app-debug-`) are evicted before normal and error segments.

## Schema, Privacy, and OSLog Visibility

- `TelemetryRecord` uses a closed flat schema of 29 top-level keys to stay far below Axiom's 256-field dataset limit. Nested diagnostic stacks serialize into the `details` JSON string.
- Never record OAuth tokens, refresh tokens, Keychain secrets, authorization codes, or `Authorization` headers.
- Every record mirrors to `OSLog` under subsystem `in.bitehaus.clinical` with `.public` formatting. Clinic debugging data and verbose SQL statements are therefore visible in Console and sysdiagnose on Release devices.
- Verbose logging is OFF by default. Enabling it in Shake -> Settings -> Diagnostics captures debug logs and expanded SQL statements (truncated to 4 KB) and automatically turns off after 24 hours.

## Silent-Failure Rule

- Telemetry failures never badge `BackupWarningToolbar`, never interrupt clinic workflows, and never use `BackupCoordinator`'s background task.
- Upload errors (including `401`/`403` token rejections and Axiom `200` partial failures where `failed > 0`) appear only inside Settings -> Diagnostics.

## Axiom Setup and Token Rotation

Configure three Xcode build settings on the `clinical-swift` target (read through `Info.plist`):

- `AXIOM_INGEST_DATASET`: `clinical-dev` for `Debug` and `Release[sdk=iphonesimulator*]`; `clinical-prod` for `Release`.
- `AXIOM_INGEST_URL`: Set to the regional Axiom edge endpoint `https://eu-central-1.aws.edge.axiom.co/v1/ingest/$(AXIOM_INGEST_DATASET)` (legacy `https://api.axiom.co/v1/datasets/$(AXIOM_INGEST_DATASET)/ingest` is also supported).
- `AXIOM_INGEST_TOKEN`: Write-only ingest token scoped strictly to its target dataset. Leave empty to keep telemetry local-only.

For AI agent queries against EU-region Axiom organizations, connect the hosted MCP endpoint `https://mcp.eu.axiom.co/mcp`.

To rotate a token, create a new ingest-only token in Axiom, update `AXIOM_INGEST_TOKEN` in Xcode build settings, ship the new build, and revoke the old token after adoption. If a token is revoked while deployed, the app halts automatic uploads on `401`/`403`, keeps segments on disk up to the 20 MB cap, and reports the error in Settings -> Diagnostics.
