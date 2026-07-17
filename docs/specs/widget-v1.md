---
status: implemented
---

# Home Screen Widget v1

## Summary

Add an iOS Calendar-like large Home Screen widget that shows the dentist today's remaining
appointments followed by appointments on the next two calendar dates. The widget is a compact,
chronological glance at the immediate schedule rather than a substitute for the full Schedule tab.

## Core Chronological Principle

Dates in the widget must be consecutive calendar dates.

- Today is always the first date.
- If another date is shown, it must be tomorrow.
- If a third date is shown, it must be the day after tomorrow.
- Never skip an empty date to show a later date with appointments.
- Keep an empty date visible with its empty-state message when that date's section fits.

This predictable sequence is more important than surfacing a later non-empty date. Skipping dates
would require the user to carefully read every header and could cause an appointment two days away
to be mistaken for tomorrow's appointment.

## Appointment Eligibility

- Include non-cancelled appointments whose end time is after the current time.
- This includes an appointment already in progress and excludes appointments that have ended.
- Group eligible appointments by calendar date and order them by start time ascending.
- Today remains visible even when it has no eligible appointments.

## Date Sections

- Show between one and three date sections, subject to the available height.
- Add sections only in chronological order. If the next consecutive date cannot fit, do not show a
  later date instead.
- The first section header shows today's date in the accent color. Later section headers use the
  secondary color.
- Use the same compact date format for every section, without relative labels such as `Today` or
  `Tomorrow`. Example: `Monday, 15 Mar`.
- Distinguish today's header from the two future headers through color only.
- When today has no eligible appointments, show `No more appointments today`.
- When either future date has no eligible appointments, show `No appointments`.
- An empty Sunday overrides those standard empty states: whether it is today or a future date, show
  `Vacation day 🌻` instead. If Sunday has appointments, show them normally.

## Appointment Cards

- Lay out appointments one by one within their date section rather than on a time-scaled timeline.
- Give all visible appointment cards equal height.
- Show the appointment's status icon, start time, and patient name.
- Use the app's existing patient-name fallback when no patient name is available.
- Give the card an accented thick leading border and a treatment visually related to the in-app
  appointment cards.

## Capacity and Exact Fit

The widget's usable content rectangle is the area inside the standard system widget margins.

- Fill the usable content rectangle cleanly, without partial rows, clipping, overflow, extra
  spacing, or an extra gap after the final visible row.
- Appointment row heights may adapt to the widget's available size by 2–4 points from their
  standard height, preserving the intended compact card appearance.
- Choose the number of visible appointment rows together with their row height so the final visible
  row ends at the bottom of the usable content rectangle.
- Show no more than the three consecutive date sections defined above.
- Empty usable space is acceptable only when all content for those three dates is visible and there
  are too few appointments to fill the widget. Do not show a fourth date or stretch cards beyond
  their acceptable height range merely to consume that space.

When appointments within the last visible date section do not fit:

- Use the final available row for an `N more appointments` summary.
- The count includes the eligible appointments hidden from that date section.
- Use the singular `1 more appointment` when appropriate.
- The summary is part of the section and counts as its final row for layout purposes.
- Never render a partially visible appointment card or summary row.

## Interaction

- Selecting an appointment card opens the app directly to that appointment's details sheet.
- Selecting a date section outside an appointment card opens the Schedule tab on that section's
  date. This includes its header, empty-state message, and otherwise empty area.
- Selecting an `N more appointments` summary opens the Schedule tab on that summary's date.
- Appointment-card selection takes precedence over the surrounding date-section destination.

## Acceptance Criteria

- The widget always begins with today, including when today has no remaining appointments.
- Every later visible section is the next consecutive calendar date; an empty date is never skipped
  to surface a later appointment.
- The widget shows no more than today, tomorrow, and the day after tomorrow.
- Only non-cancelled appointments ending after the current time appear, ordered by start time within
  each date.
- Each appointment card shows a status icon, start time, and patient name with an accented leading
  border.
- Selecting an appointment card opens the correct appointment details sheet.
- Selecting a section's header, empty state, empty area, or overflow summary opens the Schedule tab
  on that section's date.
- Every date header uses the same date format; only today's header uses the accent color.
- An empty Sunday shows `Vacation day 🌻` instead of the standard empty-state message; Sunday
  appointments render normally when present.
- When all eligible appointments do not fit, the last available row shows the correct singular or
  plural hidden-appointment count for its date.
- Content uses the full rectangle inside the standard widget margins whenever the three-date
  content is sufficient, with no clipped or partially visible rows.
- Empty space remains only when all content across the three consecutive dates is already visible
  and the card-height bounds prevent a clean further expansion.
