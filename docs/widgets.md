# Widget Architecture

This document captures the cross-process and layout constraints for Clinical widgets.

## Shared database ownership

- The app and widget use the App Group `group.in.bitehaus.clinical` and share `SQLiteData.db`.
- Simulator builds must preserve code signing. Disabling signing strips the App Group entitlement,
  which makes the shared container unavailable before the database can open.
- The app is the only schema and write owner. It creates the database, runs migrations, and enables
  persistent WAL mode before the widget can read it.
- The widget opens a coordinated, read-only `DatabasePool`. It must never run migrations, seed
  records, or create an empty replacement database when the shared database is unavailable.
- Both processes coordinate opening the database with `NSFileCoordinator`. Persistent WAL mode is
  required because a read-only extension cannot recreate missing WAL or shared-memory sidecars.
- The app observes committed changes to `appointments` and `patients` at the database boundary and
  asks WidgetKit to reload the schedule timeline. Do not scatter reload calls across individual save
  paths.

## Timeline invariants

- Timeline entries are snapshots, not a second storage cache. Each reload queries the shared
  database and maps records into immutable widget read models.
- The schedule refreshes at the earlier of the next visible appointment end or local midnight.
  Database commits request an additional reload.
- The widget query owns its cancellation and end-time filters. Views receive only eligible,
  chronologically ordered appointments.

## Layout and interaction

- Widget dates are a consecutive prefix of today, tomorrow, and the following date. A later date is
  never substituted for an empty earlier date.
- Every earlier visible section is complete. Only the final visible section may replace hidden
  appointments with an overflow row.
- `WidgetLayoutPlanner` is the single owner of capacity and row-height arithmetic. Keep those rules
  out of SwiftUI view conditionals so exact-fit behavior remains unit-testable.
- Widget appointment rows reuse `AppointmentCard` at the planner-provided frame and compose the
  widget accent stripe around it. Do not fork a second appointment-card implementation.
- Widget URLs remain thin adapters over `ClinicalURL` and router-owned external navigation.
