# Enforce Schedule–Appointment Date Consistency

## Summary

Make `Router` the sole owner of the selected schedule date, details navigation, and app-level presentation intent. Appointment sheets may open immediately from an ID, but appointment content cannot render until its observed date and the underlying schedule date agree.

Adopt latest-action-wins routing: a new app-level action permanently discards the interrupted sheet, draft, and suspended state. No previous presentation is restored afterward.

## Implementation Changes

- Replace `ScheduleModel.selectedDate` and `scheduleDateRequest` with a normalized, read-only `Router.selectedScheduleDate`.
  - Schedule strip, day pager, loading, booking previews, edits, and saves read this single value.
  - User-driven selection goes through `selectScheduleDate(_:)`; changing to a different day dismisses the shared details flow.
  - Booking/editing remains open and updates its draft when the strip changes.

- Make the details invariant structural at the routing boundary.
  - Keep appointment routes ID-based so widgets and URLs can open the sheet immediately without a preliminary database lookup.
  - The appointment destination observes its details, reports the resolved start date to the router, and renders appointment content only after the router has selected the Schedule tab and matching calendar day.
  - While resolving or aligning, show neutral sheet content; a missing appointment preserves the existing unavailable state without changing the selected day.
  - Re-run alignment if the observed appointment date changes. Guard callbacks by presentation and current-route identity so dismissed or replaced destinations cannot change the schedule later.
  - Restrict details root/path mutation to router methods. Feed `NavigationStack` a controlled binding so pushes, pops, and back navigation all pass through the same route transition boundary.

- Preserve sheet navigation history while synchronizing each visible appointment route.
  - Navigating appointment X → patient → appointment Y selects date Y.
  - Returning through the patient route leaves the current day unchanged.
  - Returning to appointment X selects date X before its details render.
  - Selecting a different date directly dismisses the complete shared details session.

- Replace parallel request optionals, request-consumption methods, suspension/restoration, and `canRequestSheet` with one app-presentation state and one latest-replacement slot.
  - Cases cover details, appointment booking/editing, appointment messaging, and patient creation/editing.
  - A new action discards the current presentation. If SwiftUI must finish dismissal first, retain only the newest requested replacement; later actions overwrite it.
  - Replacing one active details root with another reuses the stable sheet session for immediate response while clearing its history.
  - Route “Add Patient” through this state instead of local `isAddingPatient`, so every app-root sheet can be interrupted consistently. Nested pickers/forms disappear with their interrupted parent.
  - External schedule and patient-search actions clear both current and replacement presentations before updating their destination.
  - Add one authoritative `openAppointment(id:)` entry point for widgets, URLs, and future App Intents. Do not add a new App Intent now.

- Update schedule scrolling so it runs only after route/date alignment and only when the resolved appointment belongs to the selected day.

## Documentation

- Record the canonical UX invariant in the timeline architecture documentation: appointment details for date X must never be rendered over Schedule date Y; appointment-driven navigation changes the day, while direct day selection dismisses details.
- Add a short routing architecture note, linked from `AGENTS.md`, documenting the single-presentation/latest-action-wins policy.
- Remove obsolete suspend/restore guarantees from booking and patient documentation. Do not modify implemented files under `docs/specs/`.

## Test Plan

- Router tests:
  - Different-day direct selection dismisses details; selecting the same day does not.
  - Resolving an appointment selects Schedule and its day without dismissing that route.
  - X → patient → Y → back → back produces day Y and then day X while preserving history.
  - Stale resolution callbacks after dismissal, root replacement, or rapid navigation are ignored.
  - Rapid competing actions retain only the newest destination and never restore interrupted state.
  - Every app-root presentation type can be interrupted by an external appointment.
  - Missing appointments open immediately as unavailable and leave the date unchanged.

- Destination/model tests:
  - Appointment content remains gated while the schedule day is mismatched.
  - Content appears once alignment completes.
  - A live appointment-date change gates content again and realigns the schedule.

- Manual acceptance scenarios:
  - Change the strip behind appointment details and confirm immediate dismissal.
  - Change dates while booking and confirm the booking remains open with its draft updated.
  - Open widget/URL appointments over dirty booking, patient-edit, messaging, and details sheets.
  - Exercise cross-navigation and back navigation across appointments on different dates.

## Assumptions

- “Dismiss details on date change” applies to the shared appointment/patient details session, not booking/editing.
- Interrupted state is permanently discarded without confirmation or restoration.
- Active details-to-details replacement counts as interruption but remains in-place for speed.
- Existing unrelated changes in `TODO.md` and `docs/plans/share-persistence.md` remain untouched.
- Implementation remains source-only unless build or test execution is explicitly requested.
