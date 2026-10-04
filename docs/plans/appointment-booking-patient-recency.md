# Sort Booking Patients by Recency

## Goal

Put likely patients first when selecting a patient for an appointment. Support
the common tasks of booking a follow-up and booking a newly created patient.
Apply the same order to an empty search and to matching search results.

## Current Behavior

- `AppointmentBookingView` observes `patientListRowsQuery()` from
  `clinical-swift/persistence/PatientQueries.swift`. This query orders patients
  by name and includes their next scheduled appointment date.
- The booking form filters these rows with `PatientNameSearch.matches`.
  Filtering preserves the query order. Name matching uses word prefixes and
  does not depend on word order.
- A nonblank search shows `Add new patient` after the existing matches.
- The Patients tab uses the same query and then groups patients by name.

## Proposed Ordering

The work item does not define which appointment date determines recency. Use
the following rule as the implementation assumption:

1. Find each patient's latest appointment start at or before `now`. Include
   scheduled and completed appointments. Exclude cancelled appointments.
2. Use the later of that start and the patient's `createdAt` as the sort date.
   If the patient has no qualifying appointment, use `createdAt`.
3. Order by sort date, newest first.
4. For equal sort dates, put named patients first, then order by name with the
   existing case-insensitive database comparison, then by patient ID ascending.
   The ID makes the order stable when names and dates are equal.

Use the appointment start, not its creation or update date. This makes a recent
visit relevant to follow-up booking. Include past scheduled appointments because
the user might not have marked a visit as completed. Future appointments do not
increase recency because a distant booking must not take priority over a recent
visit or a newly created patient. Patient edits do not increase recency.

For example, with `now` set to 5 October 2026:

| Patient | Created | Latest qualifying appointment | Sort date |
| --- | --- | --- | --- |
| A | 5 October | None | 5 October |
| B | 1 June | 4 October | 4 October |
| C | 3 October | None | 3 October |
| D | 1 May | 20 September | 20 September |

The order is A, B, C, D. A future appointment for D does not change this order.

## Implementation

1. Add `appointmentBookingPatientRowsQuery(now:)` in `PatientQueries.swift`.
   - Keep `patientListRowsQuery` and `patientDetailsQuery` unchanged.
   - Use one observed query with one result per patient, including patients
     without appointments. Do not fetch appointment history for each patient.
   - Calculate the latest qualifying start and the sort date in the query.
     Keep these values out of `Patient` and the stored patient record.
   - Preserve `PatientDetailsSelection` and its mapping to `PatientDetails`.
     Sorting does not require a new field in the shared UI read model.
   - Preserve next-appointment metadata: the earliest scheduled start at or
     after the same `now`. Keep the past and future aggregates independent so
     the recency filter does not remove upcoming metadata.
   - Return a `Sendable` statement. Use typed StructuredQueries expressions;
     if SQL expressions are needed, bind runtime values as required by
     `docs/persistence.md`.
   - Use the existing schema and appointment indexes. No migration is planned.

2. Change the booking view to observe the booking query.
   - Obtain `now` through the registered date dependency. Capture one value
     when loading patient selection; do not change it on every search keystroke.
   - Reload with a fresh value when the patient-selection step opens again or
     the app returns to the foreground. No periodic timer is required.
   - Keep database observation active so patient and appointment writes update
     the rows without a manual cache or write notifications.
   - Keep the existing name filter and preserve the incoming order. Do not
     introduce a second sort in the view.
   - Apply this behavior to creation and editing, which share patient selection.

3. Preserve the existing booking interactions.
   - Keep `Add new patient` last for every nonblank query, including no matches.
   - Keep empty and whitespace-only searches free of a creation row.
   - Preserve patient selection, nested creation, and successful-save callbacks.
     Row updates must not replace the selected patient or change the draft.
   - Keep row content and the Patients tab order unchanged. No new strings or
     visual controls are required.

4. Add a short ordering invariant to `docs/appointment-booking.md` during
   implementation. Record the sort date, status and future-date rules, stable
   order for equal dates, and the separate Patients tab order.

## Validation

Add database query tests in
`clinical-swiftTests/AppointmentBookingPatientQueryTests.swift`. Use the existing
in-memory database and migrations, fixed IDs, and ISO-8601 dates.

- Verify that a recent appointment promotes an older patient over a patient
  with an older sort date.
- Verify that a newly created patient can precede a patient with appointment
  history. Patients without appointments remain in the result.
- Verify that multiple appointments produce one patient row and use the latest
  qualifying start, independent of insertion order.
- Cover past scheduled and completed rows, cancelled rows, future rows, and
  the exact `start == now` boundary.
- Verify that appointment creation/update dates and patient update dates do not
  determine order.
- Cover equal dates, equal names, case differences, and unnamed patients with
  stable IDs.
- Verify that next-appointment metadata still uses only future scheduled rows.
- Verify that the shared patient-list query keeps its existing name order.
- Check that matching names retain the booking order with the existing search
  matcher. Run the existing name-search tests for matching rules.
- Verify observed results after patient insertion, appointment insertion,
  rescheduling, cancellation, and deletion. Use dependency overrides and the
  repository's async database rules where required.

Run `make test`, `make build`, and `git diff --check` after implementation.
Use the configured Xcode MCP for build checks if available. On a simulator,
check empty, matching, whitespace-only, and no-match searches; confirm the
creation row stays last. Select an existing patient, create a new patient, and
return to patient selection from appointment details. Confirm the order and
draft remain correct. Repeat patient selection in edit mode.

## Scope

This change affects patient order in appointment booking only. It does not
change search matching, patient grouping, booking time suggestions, validation,
or saving. Widgets and Calendar delivery do not use booking patient search and
need no change.
