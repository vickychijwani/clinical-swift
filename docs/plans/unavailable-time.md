# Unavailable Time Implementation Plan

## Summary

Implement the [pending spec](../specs/unavailable-time.md) and the [Unavailable time artboard](https://www.figma.com/design/SE5qfKLHQwGJvN20qSc89l/Clinical?node-id=42-137).

The clinic owner can create, edit, and delete unavailable-time blocks from Schedule. Blocks appear on the app timeline, in the schedule widget, and in the existing Calendar integration. They do not affect appointment suggestions or saving.

Use these confirmed choices:

- Keep `+` for appointments. Add a separate `nosign` toolbar button.
- Show a draft block behind the editor sheet.
- Use duration choices of 15, 30, 45, 60, 90, and 120 minutes.
- Apply the three-column limit to appointments and blocks together. Keep the current overflow behavior.
- Expand the break when an appointment or block starts within it.
- Include saved blocks in the schedule widget, with the same capacity rules as appointment rows.
- Deliver block creation, changes, and deletion to the same Calendar target as appointments. Keep Clinical as the source of truth.
- Match the existing appointment card radius and typography. Use Figma for the block colors and symbol.

## Storage and Interfaces

- Add separate `UnavailableTime` domain and `UnavailableTimeRecord` database types. Store UUID, optional label, start, duration in minutes, and standard creation and update timestamps.
- Append a migration for an `unavailableTimes` STRICT table and a start-time index. Follow the existing UUID primary-key policy. Require positive duration. Do not change earlier migrations.
- Convert blank labels to `nil` with the existing string helper. Display “Blocked” when the label is absent.
- Add observed block queries to `ScheduleModel`. Load the same seven-day window used by appointment paging. Keep appointment reads and block reads separate.
- Make query builders and records safe for async SQLiteData access under default MainActor isolation.
- Add an unavailable-time editor request to the router’s single `AppPresentation` state. Support create and edit purposes. Use the existing sheet dismissal and replacement sequence.
- Add a typed `TimelineItem` with appointment and unavailable-time cases. Give each case a distinct identity namespace. Place the immutable, `Sendable` item and unavailable-time domain types in `ClinicalShared` for use by both targets. Keep the SQLiteData record in the app and draft presentation state outside database records.

Blocks have no patient or appointment status. Calendar import remains outside this version. A widget block links to its Schedule date through the existing schedule URL. A Calendar block event uses a stable, ID-based block URL for event recovery and Schedule navigation.

## Editor and Schedule Behavior

- Add `Button("Unavailable Time", systemImage: "nosign")` beside the appointment action. Hide both creation actions while a schedule editor is active.
- Tap a block to open its edit form directly. Use a fitted sheet with an optional label field, start-time picker, and duration picker. Extract the existing time and duration controls for reuse without changing appointment behavior.
- Use a `@MainActor @Observable` editor model. It owns the draft, original values, save and delete state, errors, and preview scroll requests.
- Start a new block on the selected day at clinic opening with a 60-minute duration. Do not use appointment availability to select or move its time.
- Preserve saved values when editing. On date or duration changes, carry the clock time and clamp it to clinic hours with existing `TimeOfDay` APIs.
- Validate the full interval before saving: positive duration, start at or after opening, and end at or before closing. Allow all break and appointment overlaps without confirmation.
- Keep the date strip active behind the sheet. Date changes move the draft and Schedule selection together.
- Show exactly one draft preview. Omit the saved block while editing it. Disable appointment and block selection during either schedule editor, while keeping scrolling and date selection active.
- Use the same timeline scale for rendering and scrolling. Reserve the existing editor clearance and reveal the draft after date, time, or duration changes.
- Use `ConfirmingFormSheet` for cancellation and unsaved changes. Disable gesture dismissal, as in appointment booking.
- Use `AsyncButton` for save and `ConfirmingAsyncButton` for delete. Keep both operations mutually exclusive in the model.
- Update an existing row in one transaction. Preserve its ID and creation timestamp. Report a missing edit or delete target as an error; do not create a replacement row.
- After save or delete, keep the selected day, remove the draft, and close the editor. On failure, keep the form open.
- Apply existing router interruption rules. Ignore late callbacks from an editor that a newer presentation replaced.

## Timeline and Card Design

- Extend the existing layout engine to process typed schedule items together. Preserve half-open overlap intervals, stable ordering, column reuse, and vertical coordinate math.
- Keep at most three columns. Extra simultaneous items share column 3, as they do now. Do not add a save restriction.
- Keep appointment-only layout entry points for existing previews and other callers.
- Extend `TimelineScale` to include saved and draft blocks in break expansion. A start at break start expands it; a start at break end does not. A block that starts before the break keeps the current crossing-interval rule.
- Add an adaptive `UnavailableTimeCard`. Use the appointment card’s stacked and compact layout patterns. Keep the start time visible and constrain label content to the card.
- Match the Figma block colors and symbol: `nosign`, background `#D5E5CE`, border `#A7C19C`, time and symbol `#48603D`, and label `#2D4226`. Store the colors as named assets in the shared asset catalog and one card style configuration.
- Match the existing appointment card's 8-point corner radius for the surface, border, clipping, and hit boundary. Use one shared radius value for both card types and their app and widget wrappers. The Figma radius is 7 points, so these values are not identical.
- Reuse `styleAppointmentTime()` and `styleBodyBold()` for font metrics. Allow a color override on the time helper while preserving its appointment defaults. Both references use 12-point semibold time with monospaced digits and 14-point semibold labels. The app uses 0.4-point time tracking and native line height; Figma uses 0.5-point tracking and explicit 15/18-point line heights. Use the app values, including its label clipping and scale behavior. Keep app timeline card height tied to duration.
- Apply the intended button frame before `contentShape`. Ensure clipped label content cannot receive taps outside the card.
- Keep existing Schedule chrome, appointment styles, and native system controls.

## Widget Display

- Extend `WidgetScheduleSection` to hold an ordered list of typed schedule items. Read appointments and blocks in the same database read transaction, then merge them by start, end, and typed identity. Preserve the current appointment status filters.
- Read blocks with the widget repository's existing raw SQL and GRDB boundary. Do not add SQLiteData to the widget or give the extension migration or write ownership. If the block table is absent before the app runs its new migration, use an empty block result and continue to show appointments.
- Include in-progress and future blocks for today and the next two dates. Exclude every item whose end is at or before the snapshot time. Draft blocks never enter widget snapshots.
- Extend `WidgetLayoutPlanner` and its planned rows to count and reference either item type. Keep the current row heights, exact-fit arithmetic, consecutive date sections, and rule that only the final visible section can have an overflow row. The widget remains a list; the app's three-column limit does not apply to widget rows.
- Put `UnavailableTimeCard` in `ClinicalShared` and reuse it at the planner's row height. Keep its green surface and `nosign` symbol. Keep the existing appointment accent stripe on appointment rows only.
- Keep appointment row links unchanged. Link block rows to `ClinicalURL.schedule` for the block's date. Opening a block row selects Schedule on that day; it does not open an editor.
- Count hidden appointments and blocks together. Keep the current appointment-only overflow text when all hidden items are appointments; otherwise use "1 more item" or "N more items". Show an empty row only when neither type has an eligible item. Use "No more items today" or "No items" for empty sections and preserve the existing Sunday message.
- Schedule the next refresh at the earlier of the next eligible appointment or block end and local midnight. Add `unavailableTimes` to the database regions observed by `WidgetTimelineInvalidator`, so committed create, edit, and delete operations request a reload.
- Include blocks in widget sample snapshots and previews. Update the widget description to include unavailable time.

## Calendar Delivery

- Use the existing one-way EventKit integration and the first writable calendar titled exactly `Bitehaus Debug`. Reuse full Calendar access, activation-time target resolution, and the dedicated EventKit actor. Do not add another permission flow or Calendar target.
- Update the Calendar permission text to: "Clinical needs Calendar access to create, update, and remove Bitehaus Debug appointment and blocked events."
- Add a device-local `unavailableTimeCalendarSync` table in an appended migration. Use `unavailableTimeID` as its primary key, with optional event identifier and last-synced start, pending flag, revision, and standard timestamps. Keep the existing appointment outbox and migrations unchanged. Do not add a block foreign key: pending removal work must survive block deletion. Exclude both outboxes from future cross-device sync.
- Add database triggers that queue work on block insertion, actual changes to label/start/duration, and deletion. Preserve the event link and advance the revision when new work arrives. A timestamp-only update must not queue delivery. Drafts and debug sample blocks must not be exported; remove sample outbox rows in the seeding transaction, as for appointments.
- Generalize the existing Calendar client, event payload, link, and coordinator names for both source types. Event payloads contain title, start, end, notes, and marker URL. Change the delete operation to accept a marker URL instead of an appointment ID. Preserve appointment event titles, notes, URLs, cancellation, completion, and recovery behavior.
- Extend the single app-owned coordinator to observe and drain both outboxes serially through the same Calendar client. Track source type and ID separately so an appointment and a block with the same UUID cannot share a link. Preserve pending work order within each source and process appointment work before block work on each pass. A failure on one item must not prevent other items from being processed.
- Send each saved block as a timed event. Use `Blocked: <label>` as the title, or `Blocked` when no label is present. Derive start and end from the stored start and duration. Use empty notes and make no Contacts request for a block.
- Store `clinical://unavailable-times/<block-id>` as the event URL. Add this case to `ClinicalURL` and resolve it through the router: interrupt the current presentation, load the block, and select Schedule on its stored date. Do not open the editor automatically. If the block is gone, show an informational error. Guard asynchronous resolution so an older result cannot replace newer navigation.
- Keep widget block links on their existing date URL. Calendar marker URLs must remain ID-based because labels and dates can change and several blocks can share a date.
- Reuse replacement, event-identifier lookup, bounded marker-URL recovery, matching-event adoption, and duplicate removal. A label or schedule change replaces the linked event. Block deletion removes it; deletion before initial delivery must also be safe.
- Apply the current revision guard to block delivery. A suspended EventKit operation must not clear newer pending work. If replacement creates an event after a newer block change or deletion, preserve its link for the pending retry. Remove a delivery row after deletion only when its revision is still current.
- Keep failed work pending for later activation when permission, target Calendar, EventKit writes, or link persistence fail. Calendar errors do not roll back block data or turn a successful block save into a form error. Use the existing diagnostic logging policy.
- Calendar-side changes never update Clinical. The next relevant Clinical change replaces them. Record the existing replacement trade-off: Calendar alarms, attendees, and manual event changes are not preserved.

## Validation and Documentation

- Test migration from the current schema and persistence after reopening the database.
- Test blank labels, create/edit/delete, preserved identity and timestamps, write failures, missing records, and repeated operation attempts.
- Test clinic boundaries, exact closing-time ends, break overlaps, date changes, and unchanged edit initialization.
- Test mixed two- and three-column groups, staggered overlap, touching intervals, stable ordering, and fourth-item overflow.
- Test saved and draft blocks at both break boundaries. Verify rendering and scroll coordinates use the same scale.
- Test observed schedule updates and paging. Verify block writes do not change appointments or their Calendar outbox. Verify block create, change, and delete operations queue their own Calendar work in the same transaction.
- Run appointment booking regression tests with blocks present. Suggestions, manual selection, and saving must give the same results.
- Test router replacement, dismissal sequencing, and late callbacks.
- Test widget queries with mixed items, blocks without appointments, overlapping items, blank labels, and stable ordering. Cover in-progress items, exact end-time exclusion, all three dates, and a database without the new table.
- Test widget capacity and overflow counts with both item types. Preserve appointment-only exact-fit results and the rule that earlier visible sections must be complete.
- Test refresh timing when a block ends first, when an appointment ends first, and at midnight. Verify committed block changes are included in the widget invalidation observation. Test block links through the existing schedule URL and router behavior.
- Test Calendar trigger delivery, revision changes, unchanged-field updates, retained links after deletion, and sample-data exclusion. Verify block events have the specified title, start, end, empty notes, and unique URL without using Contacts.
- Test Calendar create, replace, and delete delivery, including create-then-delete before delivery, identical appointment/block UUIDs, permission denial, missing Calendar, retry after restart, write failures, and revision changes during suspended work. Verify recovery does not create duplicate events and block failures do not prevent appointment delivery.
- Keep the appointment Calendar regression tests. Test block URL parsing, stored-date resolution, missing blocks, and stale navigation results. Verify the existing appointment event contract is unchanged.
- Run `make test` and `make build`. Inspect logs for errors and concurrency warnings.
- Compare the rendered Travel example with the Figma artboard for colors, symbol, and placement. Verify the radius and typography against the current appointment card. Check short cards, blank and long labels, three columns, break blocks, and adjacent card taps. Verify dense, sparse, and block-only widget previews at the planner's row heights.
- Update the timeline, persistence, routing, booking, widget, and Calendar architecture notes. Record the shared app column limit, accepted overflow limitation, mixed widget capacity, refresh rules, block event contract, durable delivery, and device-local outbox ownership. Update the documentation map description to cover appointments and unavailable time in Calendar sync.
- Keep the spec pending during planning. When implementation passes validation, record the confirmed choices and mark it implemented.

Separate visibility and selection are guaranteed for up to three simultaneous items. A fourth item can cover another card in column 3. Single-block duration remains limited to the confirmed picker choices.
