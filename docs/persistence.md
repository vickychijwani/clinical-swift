# Persistence

## Data boundaries

Keep storage details out of domain values. Read models must reflect committed
changes from every write path; screens must not maintain separate copies of
derived patient or appointment data.

Keep cancelled appointments for audit, but exclude them from normal reads by
default. A stale screen must not overwrite a newer terminal status.

Released migrations are append-only: installed databases do not rerun them.

## Shared database access

The app owns database creation, migrations, and writes. Widgets are read-only and
must report unavailable data rather than create a replacement database.

Database replacement must exclude live readers and writers in every process for
their full access lifetime. An open reader must not keep using replaced files.

See [backups](backups.md) for snapshot and recovery rules.

## Future CloudKit sync

SQLiteData with CloudKit is the intended sync system. Offline devices cannot
enforce uniqueness together; preserve globally unique, single-column primary keys
and avoid other uniqueness constraints on tables intended for sync.

Keep future staff sharing possible; it differs from syncing one person's devices.
When sharing compatibility conflicts with local data correctness, preserve
correctness and record the trade-off.

The ledger's relationships and deletion protections preserve financial history.
They need further design before CloudKit sync; do not remove them to enable sync.
See [payments](payments.md) and [Calendar](calendar-sync.md) for ownership rules.

Before implementing sync, check SQLiteData's [sync](https://github.com/pointfreeco/sqlite-data/blob/1.12.1/Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md)
and [sharing](https://github.com/pointfreeco/sqlite-data/blob/1.12.1/Sources/SQLiteData/Documentation.docc/Articles/CloudKitSharing.md)
requirements. Library conflict resolution is not an app-level guarantee.
