# Architecture boundaries

The policy is defined in [the Swift checker](../scripts/check_architecture.swift).
The app uses `ClinicalModels` and `ClinicalPersistence`. Persistence uses models.
The widget uses models and compiles `ClinicalShared` with the app. Shared database
code keeps the widget a coordinated read-only client. The app owns migrations
and writes. Keep the standard SwiftPM `Sources/` and `Tests/` layout.

**ARCHITECTURE POLICY — EXPLICIT HUMAN APPROVAL REQUIRED**

These rules protect clear ownership and dependency boundaries.
Passing the check is necessary, but does not prove a sound design.

Do not change rules, add exceptions, or disable checks merely to pass.
Do not bypass a boundary by copying existing logic, adding a parallel
implementation, or moving code where the checker cannot detect it.

First, look for a solution that preserves shared ownership and satisfies
the existing boundaries. Do not force a solution that adds duplication
or unnecessary complexity.

If the boundary prevents a clean solution, report the conflict and
propose the smallest code or policy change. Obtain explicit human
approval before changing the policy. A feature or refactor request
does not itself authorize that change.

Keep approved policy changes separate from feature or refactor changes,
so the human reviewer can inspect them directly.

## Display ownership

Display components receive domain values and action closures. Their imports
must not include persistence libraries. The check covers feature `views/`,
shared display files, app `widgets/`, and the backup and unavailable-time editor
views. `utils/` is not a separate layer: its Binding helpers can use SwiftUI,
and date helpers can use models.

The file-level exceptions are explicit:

| Files | Reason |
| --- | --- |
| PatientsView, PatientDetailsView | Outer screens own SQLiteData observations and map rows to domain values for child views. |
| AppointmentBookingView | The outer screen observes patient choices for booking. Child rows receive domain values. |
| ScheduleView | The preview supplies a database to the schedule model. |
| AppointmentDetailsView, AppointmentMessageView, EditPatientView | Previews set up database dependencies for their models. Only the SQLiteData import is allowed by this exception. |
| ClinicalSharedDatabase, ClinicalDatabaseAccess, WidgetScheduleRepository | Shared infrastructure owns coordinated reads and database access, rather than display. It cannot import ClinicalPersistence. |

Preserve observed queries when moving query ownership into screen models.
Manual caches can miss writes from another path and leave screens stale.

## Checks and limits

Run `sh scripts/check_architecture.sh` for the working tree, or add `--staged`
to check the Git index. The staged check takes a temporary snapshot, including
the manifest, project, and unchanged source files. It does not edit source.
The pre-commit hook runs it before formatting. CI runs it on Linux and macOS.
macOS also requires Xcode product and source membership checks through `plutil`.
The executable is cached in Git metadata until its source or compiler changes.
Run `sh scripts/test_architecture.sh` to test the checker.

SwiftPM's explicit dependency import check rejects undeclared direct imports.
The policy checker also rejects forbidden declared dependencies. Neither check
proves write ownership or domain-only view inputs within the app module. Review
these rules in code and retain model tests. A view can call `model.save()`;
keyword bans cannot distinguish this from direct database access.

Run `swift scripts/check_package_versions.swift` from the repository root to
compare shared dependency versions and revisions. Platform-only pins can differ.
For dependency updates, change the exact manifest requirement and both resolved
files as needed in one PR. CI disables automatic package resolution so each
manifest is checked against its committed pins.
