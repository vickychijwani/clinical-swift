# Calendar Sync

This document captures the invariants for the one-way EventKit integration.

## Ownership and Target

- Clinical is the source of truth. Calendar changes never write back into the app.
- Events belong to the first writable calendar whose title is exactly `Bitehaus Debug`. Resolve that
  calendar from EventKit on every app activation; do not persist its identifier or offer a picker.
- Full Calendar access is required because the app must enumerate calendars and manage previously
  created events.
- The EventKit store belongs to a dedicated actor. Calendar enumeration, recovery searches, and
  writes are synchronous EventKit operations and must not run on the main actor.
- Calendar-side edits are left alone until the corresponding appointment or patient changes in
  Clinical. That change replaces the managed event with Clinical's current values.

## Event Contract

- The event title is the patient's current display name.
- Start and end come from the appointment start and duration.
- Notes are exactly two lines: `Name: <contact name>` followed by
  `Phone: <normalized patient phone>`. Missing values remain blank after the colon.
- Resolve the contact name when creating or replacing an event. Do not persist or independently
  observe contact names.
- Store `clinical://appointments/<appointment-id>` in the event URL for recovery and deep linking;
  keep bookkeeping metadata out of the notes.
- Cancellation and hard deletion remove events. Completion retains them.

## Durable Delivery

- `appointmentCalendarSync` is both an EventKit link and a transactional outbox. Database triggers
  create or mark its rows pending in the same transaction as appointment and relevant patient
  changes.
- The table deliberately has no appointment foreign key, allowing pending deletion work to survive
  an appointment or patient cascade deletion.
- The migration does not enqueue existing appointments. A pre-existing appointment enters Calendar
  only after a later relevant Clinical change.
- Debug sample appointments are removed from the outbox in their seeding transaction; demonstration
  data must never reach the device owner's `Bitehaus Debug` calendar.
- The app observes committed outbox changes while running and retries pending rows on later
  activations. Calendar failures never roll back appointment data.
- A revision guards suspended EventKit work from clearing a newer database change. Event identifiers
  and last-synced starts support direct lookup and bounded URL-marker recovery.
- The table is device-local integration state. Exclude it from any future CloudKit or other
  cross-device database synchronization because EventKit identifiers are local to a device's event
  store.

## Unavailable-time delivery

- A block event is timed. Its title is `Blocked: <label>` or `Blocked` without a label. Its marker is `clinical://unavailable-times/<UUID>`.
- Block insert, actual label/start/duration change, and deletion queue work transactionally in `unavailableTimeCalendarSync`. Timestamp-only and unchanged-field updates do not queue work. Seed transactions remove sample block delivery rows.
- Keep source type and UUID separate. Read pending work in order for each source, and process appointments before blocks on each pass. One item failure must not stop other work.
- A revision guards every suspended replacement and deletion. If a newer change arrives during replacement, retain the new event link without clearing pending work. Delete an outbox row only if its revision still matches.
- Permission, target, write, or link-persistence failures leave work pending for a later activation. They cannot roll back block data or turn a successful editor save into a form error.
- Both outboxes belong to this device and must not join future cross-device sync.

## Replacement Trade-off

Updates delete and recreate the event. This keeps the Calendar client to replacement and deletion,
but EventKit cannot make those two writes atomic. A failed creation stays pending for retry, and URL
marker recovery avoids duplicates after a creation succeeds before the link is persisted.

Replacement intentionally discards Calendar-side alarms, attendees, attachments, and other manual
customizations. Use in-place event updates instead if preserving those properties becomes a future
requirement.

## Backup recovery

The snapshot is authoritative for its linked records. Fix the cutoff at the local
start of day seven calendar days before recovery. Queue restored items with saved
links or pending work whose end is at or after the cutoff, including previously
synced rows and future items. Do not add records that have no saved Calendar row;
they can be pre-integration data or samples deliberately excluded from Calendar.
Deleted sources use their last-synced start; older or unknown tombstones
stay stored but do not replay. Preserve link hints and every historical record.

A private recovery table retains that cutoff until each revision succeeds.
Recheck source eligibility before delivery, since a newer edit can move an item
outside the window. Validate URL marker, target calendar, and cutoff even for a
direct event ID. Shared marker indexes query from the cutoff through ten years
ahead, extended through every linked/source date. Each EventKit query covers at
most three years. An event moved beyond both bounds with a changed identifier can
be missed. Query access failure must remain pending, never become an empty match.
EventKit's synchronous query API has no separate server-error result.

Reuse replacement/deletion and revision guards. An empty successful search permits
creation. A failed item does not stop other items; activations and event-store
changes retry it. Delivery yields between batches. Newer Calendar values are
replaced with snapshot values. Delayed iCloud visibility can leave a duplicate.
Events created only after capture and unrelated events remain untouched. Calendar
has no full rollback engine in this feature.
