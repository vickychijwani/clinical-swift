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

- Working with SQL / SQLiteData, CloudKit sync, and record/domain boundaries: `docs/persistence.md` (CloudKit / sync stuff should be moved into a separate file when we implement that feature)
- Assisted patient-data recovery procedure and limits: `docs/patient-data-restore.md` (backup and restore implementation is pending; user-facing screens are deferred)
- Appointment schedule / Timeline architecture and break layout principles: `docs/timeline.md`
- Appointment booking validation and scheduling principles: `docs/appointment-booking.md`
- Horizontal date strip paging and calendar-week principles: `docs/date-strip.md`
- Patients list grouping, search, and unknown-patient principles: `docs/patients.md`
- Test structure, dependency overrides, and async database access: `docs/testing.md`
- WidgetKit, App Group database access, timeline refresh, exact-fit layout, and widget routing: `docs/widgets.md`
- App-level presentation ownership, details navigation, and interruption policy: `docs/routing.md`
- One-way EventKit appointment and unavailable-time sync, durable delivery, and Calendar ownership: `docs/calendar-sync.md`
- Patient data backups, Google account binding, release checks, and assisted restore: `docs/backups.md`

Keep the documentation map and the documents it points to up-to-date when changing the related architecture.

Files under `docs/specs/` are feature specifications - mutable while in `pending` state, and immutable once `implemented`. When a pending spec is implemented, update its status.


## Documentation Guidance

- Documentation should capture durable decisions, invariants, edge cases, and non-obvious constraints that future agents are likely to break.
- Documentation should not restate the current implementation shape, file-by-file flow, or code that is already clearer as source.
- When documenting what not to do, briefly explain why so future agents understand the tradeoff instead of treating it as a preference.
- Prefer short architecture notes over walkthroughs. If a detail will go stale as code moves, leave it out or describe the invariant behind it.

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
