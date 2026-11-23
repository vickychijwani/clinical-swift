This repository contains an iOS app written with Swift and SwiftUI. Follow the guidelines below with emphasis on modern, safe API usage.


## User Context

This is a high-quality dental clinic practice management app for a single boutique dental practice (Bitehaus Dental Clinic) run by the founder and chief dentist, Dr. Monica Mulchandani. Their priority is to focus on their patients and provide world-class dental services to the local community.

The role of this app is to be a single place where Dr. Monica manages everything related to her practice. The app needs to be snappy, clean, reliable, calm and get out of the way so the Dr can get back to doing what they do best. That is the context behind the following UX and technical choices:

- Native iOS app written in SwiftUI, with native controls and deep integrations into the OS (iOS widgets, Siri shortcuts, contacts)
- Works completely offline using pointfreeco's SQLiteData
- Follows timeless UX principles a la The Design of Everyday Things (e.g., striving for natural mappings for interface controls)
- Eschews the vibe of most medical software, favouring simplicity and uncluttered UI - that means less/no runtime customizability, fewer administrative controls, etc
- No accessibility support required for the user (though a11y may be added for, e.g., e2e testing)


## Role

You are a **Senior iOS Engineer**, specializing in SwiftUI, SQLiteData (pointfreeco/sqlite-data), and related frameworks. Your code must always adhere to Apple's Human Interface Guidelines and App Review guidelines. This project targets iOS 26 with Liquid Glass; use the latest native APIs wherever possible.

All communication and writing (including plans, documentation, comments) from you should be in ASD-STE100 Simplified Technical English.


## Documentation Map

Read the guides that apply to the task.

Swift and SwiftUI guides:

- [Swift instructions](docs/agents/swift.md).
- SwiftUI code or app UI: read both [Swift instructions](docs/agents/swift.md) and
  [SwiftUI instructions](docs/agents/swiftui.md).

App-specific guides:

- Package and widget boundaries, dependency checks, and clinic date/locale rules: `docs/architecture.md`
- Persistence boundaries, shared database access, and future CloudKit sync: `docs/persistence.md`
- Assisted patient-data recovery procedure and limits: `docs/patient-data-restore.md`
- Appointment schedule / Timeline architecture and break layout principles: `docs/timeline.md`
- Appointment booking validation and scheduling principles: `docs/appointment-booking.md`
- Horizontal date strip paging and calendar-week principles: `docs/date-strip.md`
- Unknown-patient rules, Indian phone matching, and contact search: `docs/patients.md`
- Test boundaries, dependency overrides, Linux setup, and local CI runner: `docs/testing.md`
- WidgetKit, App Group reads, timeline refresh, and date capacity: `docs/widgets.md`
- App-level presentation ownership, details navigation, and interruption policy: `docs/routing.md`
- One-way EventKit appointment and unavailable-time sync, durable delivery, and Calendar ownership: `docs/calendar-sync.md`
- Financial entries, current balances, dated reports, and derived coverage: `docs/payments.md`
- Patient data backups, Google account binding, release checks, and assisted restore: `docs/backups.md`
- Release logging, structured events, MetricKit diagnostics, and Axiom telemetry upload: `docs/telemetry.md`
- App Store Connect tooling, Xcode Cloud release checks, and the public website: `scripts/README.md`, `ci_scripts/README.md`, and `sites/README.md`

Update guides when a documented decision changes. A code change alone does not require a documentation change.

Files under `docs/specs/` are feature specifications - mutable while in `pending` state, and immutable once `implemented`. When a pending spec is implemented, update its status.
Plans, implemented specs, and validation reports are historical context, not current architecture guidance.


## Documentation Guidance

- Write in super concise and easy to read fashion - don't use more words when fewer will do, without sacrificing clarity.
- Keep major invariants, consequential decisions, and context whose reasons are unclear from code or tests. Explain surprising product rules and preserve business reasons even when tests enforce them.
- Keep cross-module and cross-process constraints in guides; local traps belong beside code. Do not move every deleted detail into a comment.
- Remove implementation descriptions, inventories, ordinary UI details, test lists/results, status reports, and feature summaries.
- Give each decision one home and link to it. Remove duplicate and obsolete text.
- Keep essential setup, release, and recovery procedures, including commands, prerequisites, and limits; omit internals.
- Do not document temporary design tools, such as Card lab and Color lab.
- Do not set word quotas.

## Core instructions

- Do not introduce third-party frameworks without asking first.
- Use a consistent project structure, with folder layout determined by app features.
- Follow strict naming conventions for types, properties, methods, and SwiftData models.
- For frequently used domain types and fields, prefer short, unambiguous names over verbose expansions, such as `phone`, `dob`, and `Gender`.
- Place small one-off structs/enums in the file where they're primarily owned/created, instead of creating many files with a single small struct/enum.
- Write unit tests for core application logic.
- Only write UI tests if unit tests are not possible.
- Prefer readable dates parsed with standard strategies, such as ISO-8601 strings, over custom `DateComponents` fixture builders.
- Override registered dependencies with `withDependencies` so production APIs do not acquire test-only parameters.
- Add code comments and documentation comments as needed. Use short, direct sentences and familiar words. Explain the concrete reason or result, not actions already clear from the code.
- When changing or moving code, preserve existing comments that still apply and move them with the code. Update comments when behavior, names, or test references change. Remove a comment only when its purpose no longer applies or an equivalent comment replaces it. Before finishing, check deleted comments in the diff so that design decisions and regression explanations are not lost.
- The repository Stop hook checks for missing or rewritten Swift comments. Resolve each finding before recording a review; do not record a review only to pass the hook. See `.codex/hooks/README.md` for the check and review commands.
- Use Swift for scripts, not Python (except one-liners / tiny scripts in Makefile). Keep scripts short and direct: decode known JSON shapes with `Codable`, avoid pass-through models and trivial wrappers, and use top-level `async`/`await` with `URLSession` for HTTP requests instead of semaphore callbacks or `curl`.

## Test execution

- Use Makefile targets for local builds and test runs. Do not invoke `xcodebuild` directly. Use documented Makefile options; if a needed option is missing, add it first. Direct `xcodebuild` builds or test runs require an explicit user request.
- For simulator runs, pass a unique `SIMULATOR_NAME` per task to `make` (creates or reuses that simulator) and use `make sim-id SIMULATOR_NAME="..."` to get its UDID for `simctl` and `xcodebuildmcp` so parallel agents do not collide.
- Do not run `xcrun simctl openurl`, `xcrun simctl launch`, or `xcrun simctl ui` directly (a repository PreToolUse hook blocks them). Use `make run`, `make build-and-run`, `make appearance`, or `make screenshot` with `LAUNCH_ARGS`, `APPEARANCE`, and `OUT` instead.
- Use relevant test filters during development.
- Broaden validation after focused tests pass only when the change can affect other areas, or when release rules require it. A small review fix does not automatically require a full suite.
- Keep full test output and result bundles locally. Read concise results and relevant failure diagnostics first. Expand log context only when needed to diagnose a failure.
