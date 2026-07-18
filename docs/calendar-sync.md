# Appointment Calendar Sync

This document captures the invariants for the one-way EventKit integration.

## Ownership and Target

- Clinical is the source of truth. Calendar changes never write back into the app.
- Events belong to the first writable calendar whose title is exactly `Bitehaus`. Resolve that
  calendar from EventKit on every app activation; do not persist its identifier or offer a picker.
- Full Calendar access is required because the app must enumerate calendars and manage previously
  created events.
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
  data must never reach the device owner's real Bitehaus calendar.
- The app observes committed outbox changes while running and retries pending rows on later
  activations. Calendar failures never roll back appointment data.
- A revision guards suspended EventKit work from clearing a newer database change. Event identifiers
  and last-synced starts support direct lookup and bounded URL-marker recovery.
- The table is device-local integration state. Exclude it from any future CloudKit or other
  cross-device database synchronization because EventKit identifiers are local to a device's event
  store.

## Replacement Trade-off

Updates delete and recreate the event. This keeps the Calendar client to replacement and deletion,
but EventKit cannot make those two writes atomic. A failed creation stays pending for retry, and URL
marker recovery avoids duplicates after a creation succeeds before the link is persisted.

Replacement intentionally discards Calendar-side alarms, attendees, attachments, and other manual
customizations. Use in-place event updates instead if preserving those properties becomes a future
requirement.
