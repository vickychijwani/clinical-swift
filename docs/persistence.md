# Persistence

## Data boundaries

Keep database records and query projections behind the persistence boundary. Domain
values must not depend on a join's shape or contain stored copies of derived
appointment metadata. Use observed queries for live read models: manual caches
require every write path to send notifications and can miss changes.

Cancelled appointments remain stored for audit use but are excluded from normal
reads at the query boundary. Callers must opt into retained cancelled data rather
than each screen remembering a filter. Status changes read, validate, and write in
one transaction so a stale screen cannot overwrite a newer terminal state.

Released migrations are append-only. Changing old SQL does not update databases
that already recorded that migration as complete.

## Shared database access

The app owns database creation, migrations, and writes. A widget must report
unavailable data rather than create a replacement database. Persistent WAL mode is
required because a read-only process cannot recreate missing WAL/SHM sidecars.

Coordinate the entire widget read, including pool closure, on the shared database
URL. Restore and rollback coordinate replacement on that same URL; coordinating
only connection opening would let a reader keep using replaced files. Process-local
access records also exclude live pools during replacement in the same process.

Do not hold a separate OS file lock for a pool's lifetime. GRDB suspension does
not release that lock, and iOS can terminate a suspended process with `0xdead10cc`.
See [backups](backups.md) for snapshot and recovery rules.

## Future CloudKit sync

SQLiteData with CloudKit is the intended sync system. Preserve globally unique,
single-column primary keys and avoid additional uniqueness constraints on tables
intended for sync: independent offline creation cannot enforce global uniqueness.

Keep future staff sharing possible, but distinguish it from syncing one person's
devices. Multiple foreign keys can prevent CloudKit sharing. Prefer compatible
relationships when practical; keep local data correctness when the two conflict
and record the trade-off with the schema decision.

The ledger deliberately uses multiple references and restrictive deletion to
protect financial history. The pinned CloudKit integration does not accept
`ON DELETE RESTRICT` on synced tables, so enabling sync needs further design work.
Do not remove those protections merely to enable sync. See [payments](payments.md)
and [Calendar](calendar-sync.md) for their data ownership rules.

Before implementing sync, check schema, migration, trigger, and conflict behavior
against SQLiteData's [sync](https://github.com/pointfreeco/sqlite-data/blob/1.6.6/Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md)
and [sharing](https://github.com/pointfreeco/sqlite-data/blob/1.6.6/Sources/SQLiteData/Documentation.docc/Articles/CloudKitSharing.md)
requirements. Library conflict resolution is not yet an app-level guarantee.
