# Calendar integration

Clinical is the source of truth. Calendar edits do not change clinic data. The
next relevant Clinical change overwrites manual Calendar customizations.

## Delivery across systems

A Calendar failure must not undo a clinic save or lose pending work, including
deletions. Failed replacements remain retryable because Calendar replacement is
not atomic. One failed item must not block others, and older work must not mark a
newer edit as delivered. Samples must never create events in the owner's calendar.

Calendar delivery state belongs to one device and must not follow clinic data
into cloud sync. Calendar work must not block clinic interaction.

## Backup recovery

The seven-day cutoff limits Calendar reconciliation, not restored clinic history.
Keep it fixed across retries. Only previously linked records or pending work take
part; other records may be old data or excluded samples. Keep older deletion
evidence without replaying it.

Within that window, the snapshot replaces linked Calendar values. Failed searches
must leave work pending. Delayed iCloud visibility can still cause duplicates, and
events created after capture can remain. Database rollback cannot undo Calendar
changes already delivered.

See the [restore procedure](patient-data-restore.md) for operator steps.
