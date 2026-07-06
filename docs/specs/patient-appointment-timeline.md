----
status: implemented
----

# Patient Appointment Timeline

## Summary

Add a latest-first timeline of appointments to the patient details sheet. The timeline gives the
dentist the patient's complete non-cancelled appointment history and allows each appointment to be
opened without leaving the existing details-sheet navigation flow.

## Timeline Content

- Present patient details as one vertically scrolling page containing, in order:
  - the existing patient summary card;
  - the existing Call and WhatsApp actions;
  - an `Appointments` section.
- The whole page scrolls together. Do not pin the patient summary or contact actions above a
  separately scrolling appointment list.
- Include every appointment whose status is `scheduled` or `completed`, regardless of whether its
  start is in the past or future. Exclude `cancelled` appointments.
- Sort appointments by start date descending. A later future appointment therefore appears before
  an earlier future or past appointment.
- Keep ordering deterministic when start dates match: use creation date descending and appointment
  ID descending as tie-breakers.
- Load the complete non-cancelled timeline. Do not add pagination, filtering, grouping, or separate
  upcoming/history sections. Use lazy view construction so a long history does not require every
  card to render at once.
- Keep the timeline live with the underlying SQLite data so appointment changes are reflected when
  patient details is active or revisited.

## Appointment Cards

- Reuse the compact patient-timeline variant of the appointment details card rather than creating
  another appointment presentation.
- Show the appointment date and time range together with an explicit `Scheduled` or `Completed`
  status label. Do not communicate status through color alone.
- Give scheduled appointments the existing active/green emphasis. Give completed appointments a
  persistent but muted secondary treatment.
- Make the complete card a button. Selecting it pushes that appointment's details onto the current
  details-sheet navigation stack.
- Back returns to the same patient details destination.
  Repeated routes such as patient A -> appointment B -> patient A remain valid and must retrace in
  order rather than being deduplicated.
- If no scheduled or completed appointments exist, keep the `Appointments` section visible and show
  a compact `No appointments yet` message in place of the card stack. Do not use a full-screen empty
  state.

## Navigation Title

- Show the inline title `Patient Details` while any part of the patient summary card remains visible
  in the scroll viewport.
- Once the summary card has fully scrolled above the viewport, replace the inline title with the
  patient's display name. Restore `Patient Details` when any part of the card becomes visible again.
- Keep the title to one line and truncate long names. Use the existing `Unknown Patient` display
  fallback when the patient has no stored name.
- The title change is presentation state only and must not alter navigation history or reset the
  scroll position.

## Data and Routing Invariants

- Query timeline appointments by patient ID and return only the appointment data needed by the
  patient-timeline card. Do not fold appointment history into the intrinsic `Patient` domain model.
  Prefer type-safe SQL queries using StructuredQueries, instead of raw SQL queries.
- Continue treating cancelled rows as retained audit data that normal user-facing reads do not
  expose.
- Reuse the existing `Route.appointment` and details-presentation path. Do not introduce a timeline-
  specific route or mutate the selected tab's navigation path.
- Preserve the existing patient-unavailable state when the patient no longer exists. Local SQLite
  reads do not need separate loading or query-error presentations.
- Preserve the current patient-sheet detent, dismissal, and cross-navigation behavior. The timeline
  must scroll within the existing patient presentation rather than adding route-specific detents.

## Acceptance Criteria

- Patient details shows its summary, contact actions, and an `Appointments` section in one scrolling
  page.
- A mixture of future and past appointments appears in descending start-date order, with stable
  ordering for equal start dates.
- Scheduled and completed appointments appear with explicit status text and distinct visual
  emphasis; cancelled appointments never appear.
- Selecting a timeline card pushes the correct appointment details in the same sheet. Back returns
  to the patient timeline.
- A patient with no visible appointments shows `No appointments yet` under the section heading.
- The navigation title remains `Patient Details` while any part of the patient card is visible,
  changes to the patient's display name only after that card fully exits above the viewport, and
  changes back when the card reappears.
- Long and unknown patient names produce a valid single-line navigation title.
- Existing sheet detents, root dismissal, unavailable states, and repeated-route navigation remain
  unchanged.

## Recommended Tests

- Query tests cover descending order, creation-date and ID tie-breakers, patient isolation,
  scheduled/completed inclusion, cancelled exclusion, and an empty result.
- View or model tests cover status labels, the compact empty state, appointment selection, and the
  patient-card visibility boundary that controls the navigation title.
- Prefer unit coverage for query, status, routing, and title-state logic. Use manual simulator
  verification for scroll-position restoration, title transitions, long histories, and sheet
  detent behavior unless those interactions cannot be validated reliably below the UI-test layer.

## Documentation on Implementation

When this feature is implemented, record the durable patient-history query and visibility semantics
in `docs/patients.md` and change this specification's status to `implemented`.
