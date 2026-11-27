# Clinical

## Context and role

Clinical is an offline-first iOS practice management app for Bitehaus Dental Clinic
(Dr. Monica Mulchandani), built with Swift, SwiftUI, and SQLiteData
(`pointfreeco/sqlite-data`).

- Keep the app snappy, calm, reliable, and uncluttered so the doctor can focus on
  patients. Favor timeless UX with natural mappings (The Design of Everyday Things),
  minimal runtime customizability, and native OS integrations (widgets, Siri
  shortcuts, contacts).
- Accessibility-specific work is out of scope unless requested (accessibility
  identifiers for e2e tests are fine).
- Work as a Senior iOS Engineer. Follow Apple HIG and App Review guidelines. Target
  iOS 27 (Liquid Glass) and Swift 6.2+ with modern native APIs.
- Write all communication, plans, documentation, and comments in ASD-STE100
  Simplified Technical English.

## Architecture

- Keep shared models and persistence (`Sources/`) independent of Apple-only
  frameworks so they run on Linux. `scripts/check_architecture.swift` enforces
  package boundaries.
- All app and widget dates, times, and formatted text use the Gregorian calendar
  in `Asia/Kolkata` with the `en_IN` locale (`ClinicDate`), regardless of device
  settings. Storage, backup, and telemetry timestamps stay UTC ISO-8601.
  `scripts/check_clinic_date.swift` rejects device defaults in production sources.

## Documentation

Read the guides that apply to your task.

Engineering and testing:

- `docs/swift.md` — Swift 6, concurrency, `@Observable`, SwiftUI layout, and interaction
- `docs/testing.md` — Test boundaries, `withDependencies`, Linux setup, and local CI runner
- `.codex/hooks/README.md` — PreToolUse and Stop hooks (build, simctl, UI waits, comments)

App and domain:

- `docs/persistence.md` — Data boundaries, shared App Group database access, and future CloudKit sync
- `docs/routing.md` — App-level presentation ownership, details navigation, and interruption policy
- `docs/schedule.md` — Timeline layout, breaks, date strip, direct editing, and appointment booking
- `docs/patients.md` — Unknown-patient rules, Indian phone matching, and contact search
- `docs/payments.md` — Patient ledger, coverage, balances, dated reports, and derived summaries
- `docs/widgets.md` — WidgetKit targets, App Group reads, refresh rules, and widget layouts

Integrations and operations:

- `docs/calendar-sync.md` — One-way EventKit sync, durable delivery, and recovery limits
- `docs/backups.md` — Google Drive backups, account binding, restore boundaries, and release checks
- `docs/patient-data-restore.md` — Assisted patient-data recovery runbook
- `docs/telemetry.md` — Local log spool, `OSLog`, MetricKit diagnostics, and Axiom upload
- `scripts/README.md`, `ci_scripts/README.md`, `sites/README.md` — App Store Connect tooling, Xcode Cloud release checks, and public OAuth pages

Documentation rules:

- `docs/specs/` holds feature specs: mutable while `pending`, immutable once
  `implemented` (update status when implemented). `docs/plans/`, implemented specs,
  and validation reports are historical context, not current architecture guidance.
- Update guides only when a documented decision changes; routine code changes do
  not require doc updates.
- Keep guides concise without setting word quotas. Record surprising product rules,
  business reasons, cross-module/cross-process constraints, and runnable setup,
  release, or recovery procedures (commands, prerequisites, limits). Omit
  implementation inventories, ordinary UI details, test lists/results, status
  reports, and temporary design tools (such as Card lab and Color lab).
- Give each decision one home and link to it. Put local technical traps in code
  comments rather than guides, without moving every removed doc detail into a
  comment.

## Code and scripts

- Do not add third-party frameworks without asking first.
- Organize app code by feature folder. Place small one-off structs and enums in
  their owning file rather than separate single-type files.
- Follow consistent naming for types, properties, methods, and database models.
  For frequent domain types and fields, prefer short, unambiguous names (`phone`,
  `dob`, `Gender`) over verbose expansions.
- Add comments as needed in short, direct sentences explaining the concrete reason
  or result, not actions clear from code. Preserve still-valid comments when editing
  or moving code, update them when behavior, names, or test references change, and
  check deleted comments in the diff before finishing.
- The Stop hook checks for missing or rewritten Swift comments. Resolve each finding
  before recording a review; do not record a review only to pass the hook. See
  `.codex/hooks/README.md`.
- Write scripts in Swift, not Python (except tiny Makefile one-liners). Keep scripts
  direct: decode known JSON with `Codable`, avoid pass-through models and trivial
  wrappers, and use top-level `async`/`await` with `URLSession` instead of
  semaphores or `curl`.

## Build and test execution

- Use `Makefile` targets for local builds and tests. Do not invoke `xcodebuild`
  directly or use `simulator-use` `app_run` or `tests_run` to build or test, unless
  the user explicitly asks; add missing options to `Makefile` first.
- For simulator runs, pass a unique `SIMULATOR_NAME` per task to `make` (creates or
  reuses that simulator) and use `make sim-id SIMULATOR_NAME="..."` for its UDID so
  parallel agents do not collide. Use `simulator-use` (not `xcodebuildmcp`) to
  inspect and drive the simulator: select that UDID with `device_use`, then use
  `ui_look`, `ui_act`, `app_logs`, `screen_record`, or `app_control`. Shut down and
  delete any one-off simulator you created (`xcrun simctl shutdown <udid>` then
  `xcrun simctl delete <udid>`) when the task is complete; do not delete pre-existing
  simulators.
- Do not run `xcrun simctl openurl`, `xcrun simctl launch`, or `xcrun simctl ui`
  directly (a `PreToolUse` hook blocks them). Use `make run`, `make build-and-run`,
  `make appearance`, or `make screenshot` with `LAUNCH_ARGS`, `APPEARANCE`, and `OUT`.
- Use relevant test filters during development. Broaden validation only when changes
  can affect other areas or release rules require it; a small review fix does not
  automatically require a full suite.
- Keep full test output and result bundles locally. Read concise results and failure
  diagnostics first; expand logs only when needed to diagnose a failure.
