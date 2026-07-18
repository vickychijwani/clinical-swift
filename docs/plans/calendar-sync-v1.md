# iOS Calendar Appointment Sync

## Summary

Implement one-way, near-real-time synchronization from Clinical to the first writable calendar titled exactly `Bitehaus Debug`.

Request full Calendar access on launch with:

> Clinical needs Calendar access to create, update, and remove Bitehaus Debug appointment events.

Full access remains necessary because the app must enumerate calendars and later locate/delete managed events. [Apple EventKit access documentation](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)

Enumerating the device’s calendars once per launch or activation is a negligible workload for this app, so do not persist a calendar identifier. Refresh EventKit sources, find the first writable exact-title match, and retain it only in memory for that active session. This cost assessment is an inference from EventKit’s local calendar-enumeration API, not an Apple performance guarantee. [EKEventStore documentation](https://developer.apple.com/documentation/eventkit/ekeventstore)

## Persistence and Coordination

- Add one device-local `appointmentCalendarSync` table that combines event linkage and durable outbox state:
  - `appointmentID` primary key.
  - Optional EventKit event identifier.
  - Optional last-synced event start for identifier-recovery searches.
  - `needsSync`.
  - Standard creation/update timestamps.
- Do not add a foreign key to appointments. The record must survive appointment and patient cascade deletion long enough to remove the Calendar event.
- Install database triggers after creating the table:
  - Appointment insert creates a pending sync record.
  - Patient, start, or duration changes mark the record pending while preserving its existing EventKit linkage.
  - Cancellation and physical deletion mark it pending.
  - Patient name or phone changes mark the patient’s non-cancelled appointments pending.
  - Completion alone does nothing because completed events remain in Calendar.
- Existing appointments receive no sync records during migration, so there is no initial backfill. A pre-existing appointment becomes eligible only after a relevant appointment or patient change.
- Document this table as device-local integration metadata that must be excluded from future CloudKit/database synchronization.
- Add a main-actor `AppointmentCalendarSyncCoordinator`, retained by `ClinicalApp.swift`, which:
  - Requests full access on launch.
  - Resolves `Bitehaus Debug` on launch and every activation without persistent target caching.
  - Observes pending sync records and drains them serially immediately after committed writes.
  - Retries retained work on later activations after permission, calendar, EventKit, or process failures.
  - Never rolls back or reports appointment operations as failed because Calendar synchronization failed.
  - Emits ordinary diagnostic logs; no privacy-redaction requirement, alerts, status screens, or settings UI.

## EventKit Boundary and Behavior

- Introduce a dependency-injected Calendar client with two operations:
  - `replaceEvent`: locate and delete the previous managed event, then create its replacement.
  - `deleteEvent`: remove the managed event if it exists.
- Own the EventKit store on a dedicated actor so its synchronous enumeration, recovery searches,
  removals, and saves never block the main actor.
- Event payload:
  - Title: current patient display name.
  - Start: appointment start.
  - End: start plus appointment duration.
  - Notes exactly: `Name: <current contact name>\nPhone: <current normalized patient phone>`.
  - Missing contact name or normalized phone produces an empty value after the colon.
  - URL: reuse `clinical://appointments/<appointment-id>` for bookkeeping and deep linking, leaving the notes exactly two lines.
- Resolve the contact name using the existing contact client whenever an event is created or replaced. Do not persist it. A Contacts-only name change is reflected the next time another Clinical change causes replacement; the app does not continuously observe Contacts.
- Continue using `PhoneNumber.normalizedE164` for the Phone line.
- Patient name and phone edits replace linked events. Cancellation and patient cascade deletion remove them. Completed appointments retain their events.
- Persist the newly created event identifier and start only after successful creation, then clear `needsSync`.
- Locate an existing event by its stored identifier. Because EventKit identifiers can become invalid after calendar synchronization, fall back to searching around the stored/current start for the unique Clinical URL marker. [Apple identifier guidance](https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemidentifier)
- If creation succeeds but database state is not updated, the retained pending record uses the URL marker to adopt the already-correct event instead of producing a duplicate.
- If deletion succeeds but recreation fails, retain the pending record; the next retry sees the old event missing and creates the replacement.
- Ignore Calendar-side edits until the next relevant Clinical change. At that point replacement restores Clinical’s data; a manually deleted event is recreated.
- If no writable `Bitehaus Debug` calendar exists, keep pending records and log the failure. If multiple matches exist, use EventKit’s first returned writable exact-title match for that activation.

Accepted tradeoff: delete-and-recreate is not atomic and discards Calendar-side alarms, attendees, attachments, or manual customizations whenever Clinical next changes that event. It may also retrigger calendar-server notifications. Durable pending state and URL-marker recovery mitigate missing or duplicate events but cannot preserve those customizations.

## Configuration and Documentation

- Add `NSCalendarsFullAccessUsageDescription` to Debug and Release app configurations with the exact purpose string above. [Apple privacy-key documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsfullaccessusagedescription)
- Add `docs/calendar-sync.md` covering one-way ownership, target resolution, no-backfill behavior, replacement semantics, retry behavior, and device-local state.
- Add the document to the `AGENTS.md` documentation map and record the local-only sync table in `docs/persistence.md`. Do not modify `docs/specs/`.
- No public app-facing APIs or user-configurable settings are added.

## Test Plan

- Migration tests verify existing appointments are untouched and future create/edit/reschedule/cancel/delete and patient name/phone changes produce the correct pending state.
- Trigger tests verify repeated mutations coalesce without losing the previous EventKit identifier/start needed for deletion.
- Payload tests cover exact notes, blank values, current contact lookup, normalized phones, display-name titles, duration-derived end dates, and Clinical URLs.
- Coordinator tests cover permission denial, first writable calendar selection, missing/read-only calendars, activation retry, serialized draining, and successful state cleanup.
- Lifecycle tests cover replacement, cancellation, patient cascade deletion, completed-event retention, contact re-resolution, patient updates, and pre-existing appointments changed after migration.
- Failure tests cover stale identifiers, URL-marker adoption, delete-success/create-failure, create-success/state-write-failure, and idempotent deletion.
- Use dependency-controlled EventKit and Contacts clients for unit tests. Implementation verification remains source-only unless build or test execution is explicitly requested.
