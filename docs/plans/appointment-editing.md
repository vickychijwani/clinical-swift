# Appointment Editing

## Summary

Reuse `AppointmentBookingView` for editing, starting on time and duration. Editing transfers to Schedule, supports patient/date changes, previews and scrolls to the draft, and remains on the selected day after save or cancellation.

## Implementation Changes

- Add an icon-only `pencil` toolbar action to scheduled appointment details; completed and cancelled appointments remain read-only.
- Route editing through an ID-based `AppointmentEditRequest` on `Router`.
  - Select Schedule and dismiss the details flow.
  - Activate editing only after sheet dismissal completes, avoiding competing presentations.
  - Preserve existing tab navigation paths.
- Have `ScheduleView` load and consume the request.
  - Select the saved date, open the editor, show one draft preview, and scroll it into view.
  - Exclude the persisted appointment from the timeline and availability input during editing.
  - Show an unable-to-edit alert if the appointment disappeared or is no longer scheduled.
- Add explicit create/edit modes to `AppointmentBookingModel`.
  - Edit mode preserves the saved patient, date, time, and duration without prefilling.
  - Open directly on “Edit Appointment”; the back chevron allows changing the patient.
  - Store `Patient` in the booking draft rather than creating partial `PatientDetails`.
- Update the existing database row on save, changing only patient, start, duration, and `updatedAt`; preserve ID, status, and `createdAt`.
- After save, dismiss and reload the destination date. After cancellation, remain on Schedule at the currently selected draft date.
- Update `docs/appointment-booking.md` with durable editing invariants.
- Add an `AGENTS.md` rule declaring `docs/specs/` immutable feature specifications that must not be edited unless explicitly requested. Do not modify `docs/specs/sheet-navigation.md`.

## Interface Changes

- Add identifiable `AppointmentEditRequest` routing state and Router request/activation/consumption APIs.
- Give the booking model an explicit create/edit purpose and unified save callback carrying the resulting date.

## Tests to Add

- Router unit tests for cross-tab transfer, dismissal sequencing, path preservation, and repeated edits.
- Model tests for exact edit initialization, patient/date/time/duration changes, and no initial prefilling.
- Persistence tests confirming in-place updates preserve ID, status, and creation timestamp.
- Regression tests covering appointment creation, discard detection, date switching, and prefilling.

Do not build, run tests, launch the app, or use the simulator until explicitly requested.

## Manual UI Checklist

- From Schedule, open a scheduled appointment and confirm the pencil appears; verify it is absent for completed/cancelled appointments.
- Tap the pencil and confirm details dismiss, Schedule remains selected, the correct date appears, the editor opens on step 2, and the draft is scrolled into view without a duplicate card.
- Change time, duration, date, and patient; verify the preview and underlying schedule follow each change.
- Save and confirm the existing appointment is updated—not duplicated—and the destination day remains visible.
- Cancel with and without changes; verify discard confirmation and that Schedule remains on the currently selected date.
- Once the patient timeline exists, repeat from Patients and confirm the transfer to Schedule behaves identically.

## Assumptions

- Editing is limited to scheduled appointments.
- Appointments may move to any date.
- Entering editing commits navigation to Schedule, even when cancelled.
- Existing unrelated `TODO.md` changes remain untouched.
