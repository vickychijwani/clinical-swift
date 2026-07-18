---
status: pending
---

# Share Persistence with the Widget

## Context

The app and widget read the same SQLite database in the App Group, but they currently use different
query boundaries. The app uses SQLiteData records and StructuredQueries, while
`WidgetScheduleRepository` uses a hand-written GRDB query and decodes untyped `Row` values. The
canonical `PatientRecord`, `AppointmentRecord`, and existing typed queries are compiled only into
the app target.

This makes the widget query locally simple, but its table names, column names, selected value types,
and decoding remain runtime-checked. Defining separate widget-only `@Table` types would remove some
of that runtime risk while creating a second schema declaration that could drift from the app's
records.

## Recommendation

Share the canonical record declarations, pure domain types and conversions, typed selections, and
read queries with the widget. Keep database ownership and mutation capabilities in the app target.

The intended boundary is:

| Shared by the app and widget | App-only |
| --- | --- |
| `PatientRecord` and `AppointmentRecord` | Writable database initialization |
| Pure `Patient`, `Appointment`, and details values needed by selections | Migrations |
| Pure record/domain conversions and validation helpers | Debug tracing and sample seeding |
| Typed selections and read queries | Status updates and other mutation APIs |
| App Group database location and coordinated read-only opening | Future sync and write coordination |

Do not move the entire current persistence folder into `ClinicalShared` unchanged. In particular,
`Database.swift` combines migrations, live writer creation, debug tracing, and sample seeding, while
`AppointmentStatusPersistence.swift` exposes write behavior. Compiling those APIs into the widget
would not execute them automatically, but it would weaken the invariant that the app is the sole
schema and write owner and would make accidental widget-side migration or mutation easier.

## Rationale

### Keep one canonical schema boundary

Both processes access the same tables, so they should compile against the same `@Table` record
types. This lets schema and query-shape changes fail at compile time in both targets and avoids
shadow record types that must be kept manually synchronized.

Typed joined selections should continue to nest complete records, following `docs/persistence.md`.
The widget repository should map a selection into its immutable snapshot model immediately rather
than exposing persistence selections to WidgetKit views.

### Share read semantics where they are genuinely common

The widget and app both need a date-bounded, start-ordered appointment/patient join that excludes
cancelled appointments. Extract or expose one parameterized StructuredQueries statement for that
common operation. Existing app entry points such as single-day and schedule-window queries can wrap
it, and the widget can provide its three-day range before applying its widget-specific
`end > timeline date` eligibility rule.

This centralizes normal cancellation visibility without forcing widget timeline policy into app
views. The repository remains responsible for producing only eligible widget appointments, as
required by `docs/widgets.md`.

### Preserve the cross-process ownership rule

The widget has the App Group entitlement and can access the database file, so source organization
is an important capability boundary even though it is not a security sandbox. Its timeline path
must only open the coordinated read-only pool. It must never create the database, run migrations,
seed samples, or perform writes.

Split `ClinicalSharedDatabase` so the App Group URL and `openReadOnly` remain shared while
`openWriter` is app-only. Keep migrations and mutations under the app source root. This makes the
supported behavior obvious and reduces the chance that future widget work calls an app-oriented
database entry point under WidgetKit's execution deadline.

## Expected Costs

### Compile time

The widget target will compile the shared record and query sources, including `@Table` and
`@Selection` macro expansion and StructuredQueries type checking. This should be a modest increase
for the current persistence surface. Package modules already needed by the app are built once per
configuration and destination, but the shared source is compiled separately for each consuming
target.

Complex StructuredQueries expressions can still stress the type checker. Keep filtering and
ordering on the appointment table before the join where semantics allow, and use a single named
intermediate statement if inference becomes slow. Do not decompose a query further without an
observed compiler need.

### Archive and installed size

The widget extension is a separate executable, so SQLiteData and any reachable dependency code are
linked into it independently of the app. This will increase the extension and overall archive size.
Release optimization and dead-code stripping should remove unused queries and conversions, so the
cost of sharing source is smaller than the cost of actively using every API.

Do not estimate the shipping delta from a Debug simulator product. Compare before-and-after Release
archives and their thinned size reports once the implementation is ready.

### Runtime performance and memory

StructuredQueries ultimately generates SQL executed through GRDB, so changing the construction of
this query should not materially change database latency. Selecting complete joined records reads
more columns than the current five-column widget projection, but the widget covers only three days
of appointments and the additional decoding cost should be negligible.

The larger extension executable may add some code and metadata pages, but executable pages are
loaded on demand. The more meaningful runtime risk is accidentally invoking migrations, seed work,
or writes from a timeline reload, which the recommended source boundary prevents.

### Maintenance coupling

Changes to shared records and queries will rebuild both targets, and all shared code must compile
under the widget's dependency and API surface. Keep shared domain code platform-neutral and move
UI, app lifecycle, contact access, sync, and other app-specific behavior into app-only extensions or
services.

## Implementation Plan

1. Move the pure `PatientRecord` and `AppointmentRecord` declarations into a shared persistence
   folder compiled by the app and widget.
2. Move the minimum pure domain values and helpers required by those records and typed selections
   into shared source. Keep UI and service behavior app-only.
3. Keep record/domain conversions shared when they are deterministic and platform-neutral. Split
   any conversion that acquires app services or dependencies into an app-only extension.
4. Add SQLiteData and the required StructuredQueries product dependencies to the widget target.
   Do not add test-support products.
5. Share the existing appointment/patient selection and expose a parameterized date-range query.
   Preserve the existing app query entry points as small wrappers where they improve call-site
   semantics.
6. Replace the raw SQL and `Row` decoding in `WidgetScheduleRepository` with the typed range query,
   then map its records into the shared `Appointment` domain value before constructing sections.
7. Split shared database access into read-only shared functionality and app-only writer
   functionality. Leave all migrations, seeding, write APIs, and invalidation ownership in the app.
8. Remove the widget-only invalid-row decoder and error case if typed record decoding makes them
   unreachable. Continue treating actual database/opening errors as timeline failures.
9. Update `docs/persistence.md` and `docs/widgets.md` only where the final implementation establishes
   a new durable invariant beyond what those documents already say.

## Verification

- Compile both the app and widget targets to catch shared-source availability and isolation issues.
- Run the existing persistence and widget repository unit tests.
- Verify that the typed widget query preserves cancellation filtering, start ordering, unknown-name
  fallback, three-day calendar boundaries, and `end > now` behavior.
- Verify the widget still opens a coordinated read-only pool and that only the app initializes and
  migrates the database.
- Inspect the generated SQL or add a query snapshot if the typed statement's range, join, filter,
  and ordering are not obvious from a focused source review.
- Compare before-and-after Release archive and thinned extension sizes to replace size estimates
  with measurements.

## Non-goals

- Do not turn the widget into a database writer or migration owner.
- Do not introduce duplicate widget-specific table declarations.
- Do not move view models, SwiftUI views, routing, contact integration, or app lifecycle behavior
  into the shared persistence boundary.
- Do not redesign the database schema or edit existing migrations as part of this refactor.
