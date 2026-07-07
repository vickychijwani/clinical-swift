# Patient Appointment Timeline

## Summary

Add a live, latest-first appointment timeline to the existing patient details sheet. Preserve the current sheet detent, unavailable state, and route history while allowing cards to push appointment details onto the same navigation stack.

## Implementation Changes

- Query appointment records with `patientTimelineAppointmentsQuery(patientID:)`, then map them to `Appointment` values using the patient name already loaded by `PatientDetailsView`.
  - Include scheduled and completed rows; exclude cancelled rows.
  - Sort by start, creation date, and appointment ID, all descending.
  - Load it through `@FetchAll` so edits and status changes update the active or revisited patient view without manual refresh.
  - Pass only mapped `Appointment` values into `ViewPatientView` so persistence types remain at the data-loading boundary.
- Extend `PatientDetailsView(id:onSelectAppointment:)` and route the callback through `DetailsRouteView` to the existing `.appointment(id)` destination.
- Rebuild `ViewPatientView` as one `ScrollView` containing the summary card, contact actions, and an `Appointments` section.
  - Use lazy construction for appointment cards.
  - Show `No appointments yet` when the history is empty.
  - Reuse `AppointmentDetailsCard`’s `.patientTimeline` variant and make the entire card invoke the route callback.
- Give the timeline card a cohesive status presentation:
  - Scheduled: explicit `Scheduled` label with the existing green emphasis and primary time text.
  - Completed: explicit `Completed` label with secondary tint and muted time text.
  - Keep the standard appointment-details variant unchanged.
- Track the summary card using `onGeometryChange` in the scroll-view coordinate space.
  - Use `Patient Details` while `summaryFrame.maxY > 0`.
  - Switch at `maxY <= 0` to `patient.displayName`, preserving the `Unknown Patient` fallback.
  - Keep the standard inline navigation title so long names remain single-line and truncated.
- After implementation, record the patient-history ordering/filtering and title visibility boundary in `docs/patients.md`, then change the specification status to `implemented`. Do not alter unrelated pending `TODO.md` changes.

## Interfaces and Types

- Reuse `AppointmentRecord` for the persistence query; do not add history to `Patient`.
- Add appointment-selection closures to the patient details views.
- Add small testable semantic helpers for timeline status presentation and summary-visibility title selection.
- No database migration, new route, third-party dependency, or selected-tab navigation mutation.

## Test Plan

- Query tests:
  - Scheduled and completed inclusion; cancelled exclusion.
  - Patient isolation and empty results.
  - Descending start order plus creation-date and fixed-UUID tie-breakers.
- Unit tests:
  - Scheduled/completed labels and active/muted presentation.
  - Title behavior for positive, zero, and negative summary `maxY`.
  - Named, unknown, and long patient display names.
  - Patient → appointment → same patient route history remains ordered and deduplicated nowhere.
- Manual simulator checklist:
  - Whole-page scrolling and exact title transition boundary.
  - Back-navigation scroll-position restoration.
  - Live refresh after editing or completing an appointment.
  - Long histories, empty state, sheet detent, dismissal, and unavailable patient behavior.
- Keep implementation verification source-only unless build, test, or simulator execution is explicitly requested.

## Assumptions

- Existing hard-coded user-facing strings remain consistent with the project because no string catalog is present.
- Standard inline navigation-title rendering provides the required one-line truncation.
- Existing SQLiteData observation supplies timeline liveness; no explicit reload lifecycle is added.
