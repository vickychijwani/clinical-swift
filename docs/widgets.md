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
- The app observes committed changes to `appointments`, `patients`, and `unavailableTimes` at the
  database boundary and asks WidgetKit to reload the schedule timeline. Do not scatter reload calls
  across individual save paths.

## Timeline invariants

- Timeline entries are snapshots, not a second storage cache. Each reload queries the shared
  database and maps records into immutable widget read models.
- The schedule refreshes at the earlier of the next eligible item end or local midnight. Database
  commits request an additional reload.
- The widget query owns its cancellation and end-time filters. Views receive only eligible,
  chronologically ordered schedule items.

## Layout and interaction

- Widget dates are a consecutive prefix of today, tomorrow, and the following date. A later date is
  never substituted for an empty earlier date.
- Every earlier visible section is complete. Only the final visible section may replace hidden items
  with an overflow row.
- `WidgetLayoutPlanner` is the single owner of capacity and row-height arithmetic. Keep those rules
  out of SwiftUI view conditionals so exact-fit behavior remains unit-testable.
- Widget appointment and block rows use the same adaptive card layout as the app at the
  planner-provided frame. Keep the accent stripe outside the shared layout so it does not appear on
  app cards.
- Widget URLs remain thin adapters over `ClinicalURL` and router-owned external navigation.

## Unavailable time

- Widget sections expose `TimelineItem` values only. Use the same API in tests and previews; an
  appointment-only view of a section can hide blocks from its consumer.
- Hidden counts include both types. Use appointment wording only when every hidden item is an
  appointment. Otherwise use “1 more item” or “N more items”. Empty sections use “No more
  appointments today” or “No appointments”; keep the Sunday message.
- Refresh at the earlier of the next eligible item end and local midnight. Observe committed block
  changes as well as appointment and patient changes to request reloads.

## Restore access

Every read pool holds the shared database access lock for its lifetime. Restore
requires an exclusive lock before replacing the database and sidecars. Release
pools promptly when a widget read finishes. A failed lock or temporary missing
database uses the existing unavailable-data path. Reload timelines after restore
or rollback; cached snapshots do not prove that the new database was read. See
[backup invariants](backups.md).
