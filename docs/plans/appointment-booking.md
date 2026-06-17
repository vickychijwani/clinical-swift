# Appointment Booking Sheet

## Summary
- Add a new appointment booking sheet from the `ScheduleView` plus button.
- Confirming the sheet persists a scheduled appointment immediately.
- Scope excludes procedure, timeline preview, and “+ New” patient creation.

## Key Changes
- `ScheduleView` presents the booking flow in a `NavigationStack`, initialized from the current schedule date.
- Wrap the booking content in `ConfirmingFormSheet`, matching the current `EditPatientView` pattern:
  - Compare a normalized booking draft against its initial value for `hasUnsavedChanges`.
  - Route the cancel toolbar `xmark` through `FormSheetDismissAction`.
  - Use the sheet’s discard alert for gesture, detent, and toolbar cancellation.
- Add a composed booking form with:
  - Toolbar cancel `xmark` on the left and confirm `checkmark` on the right.
  - Patient search by name or phone using `localizedStandardContains()`.
  - Selected patient rendered with existing `PatientRow` and an icon-only `xmark` clear button.
  - `WeekDateStrip` in a compact/sheet display mode that does not alter the existing schedule strip.
  - Compact SwiftUI `DatePicker` for hour/minute selection after date.
  - Duration picker after time with `15, 30, 45, 60, 90, 120` minutes.
- `DatePicker` nuances:
  - Initial time defaults to `Bitehaus.startTime` on the selected date.
  - On time changes, clamp to the valid clinic range.
  - Use the two-parameter `onChange` variant.

## Save And Validation
- On checkmark, require:
  - selected patient
  - start time within clinic hours
  - start + duration does not exceed `Bitehaus.closingTime`
- Insert an `AppointmentRecord` with selected patient ID, composed start date/time, selected duration, `.scheduled`, and current `createdAt` / `updatedAt`.
- After save, dismiss, set `ScheduleView.selectedDate` to the booked date, and reload schedule appointments for that day.
- Ignore break overlap and existing appointment conflicts for v1.

## Test Plan
- Unit-test booking draft time normalization: opening/closing clamps, and duration end-time validation.
- Add persistence coverage that the save path inserts a scheduled appointment returned by `scheduleAppointmentsQuery`.
- Build with the configured Xcode workflow and run the repo test entrypoint.

## Assumptions
- No procedure field is included.
- Patient search results can be a simple filtered list inside the sheet, not the full sectioned patient list UI.
