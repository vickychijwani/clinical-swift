# Calendar integration

Clinical is the source of truth. Calendar edits do not change clinic data; the next
relevant Clinical change replaces the managed event. Replacement discards manual
Calendar customizations. This keeps delivery simple, but deletion and recreation
are not atomic, so failed replacements must remain retryable.

## Delivery across systems

Calendar work is recorded in the same database transaction as its source change.
A Calendar failure must not undo a clinic save. Deletion work survives deletion of
the source record, so the delivery tables deliberately have no source foreign key.
Sample data must never create events in the owner's calendar.

Appointment and unavailable-time delivery are separate sources, even if UUIDs
match. Suspended work must not acknowledge a newer source revision, and one failed
item must not block other items. A successfully created event must remain findable
if saving its link fails; URL markers provide recovery as well as deep links.

EventKit identifiers belong to one device. Delivery state must remain device-local
when clinic data gains cloud sync. EventKit work also stays off the main actor:
its synchronous searches and writes can block the UI.

## Backup recovery

The seven-day cutoff limits Calendar reconciliation, not restored clinic history.
It is fixed at recovery and retained across retries. Only records with saved links
or pending delivery take part; unlinked records can be old data or deliberately
excluded samples. Older deletion evidence stays stored without replaying it.

The snapshot replaces linked Calendar values within that window. Failed searches
must leave work pending, not become an empty match that creates another event.
Recovery searches are bounded, and delayed iCloud visibility can still produce
duplicates. Events created only after capture have no restored link and can remain.
Restoring the local database cannot undo Calendar changes already delivered.

See the [restore procedure](patient-data-restore.md) for operator steps.
