# Appointment Booking Architecture

This document captures the deliberate constraints an agent is likely to break when changing appointment booking.

## Invariants

- Overlapping appointments are valid. The clinic can have multiple doctors attending different patients at the same time, so an existing appointment does not make that interval unavailable.
- Booking during or across the clinic break is valid. The break is a scheduling preference, not unavailable time.
- Automatic time prefilling should prefer an empty interval within the regular working segments because the clinic usually has a single doctor.
- When creating a booking for today, automatic prefilling must not suggest a past clock-minute bucket. Start the search from the next 5-minute boundary after the current clock minute, ignoring seconds, but still preserve a valid user-carried clock time when changing dates.
- Existing appointments must not restrict manual time selection or saving. Multiple doctors may be available even when the selected interval is occupied.
- Scheduling inputs inherit the normal appointment-read policy: cancelled rows are excluded before slot suggestions are calculated. Do not make each availability consumer remember to filter them.
- Patient selection uses a stable full-height sheet so search results and the keyboard do not resize it.
- Show patient creation as the last search result for any nonblank search, even when patients match. Empty and whitespace-only searches show no creation result.
- Appointment details fit the sheet to their content so the schedule remains visible. Only this step allows interaction with the schedule behind the sheet.
- The booking sheet is not manually resizable or swipe-dismissible. Explicit toolbar actions keep step changes and discard confirmation intentional.
- Creating and editing share one scheduling flow. Edit mode starts on appointment details because rescheduling is the common path, while Back still permits changing the patient.
- Appointment editing is coordinated by the Schedule tab. Entry points from a details flow permanently replace that presentation, select the appointment's day, and present the editor only after dismissal so sheets never compete for presentation.
- Starting a booking from patient details follows the same Schedule-owned handoff, with that patient preselected. The interrupted details route and navigation history are discarded rather than restored after booking ends.
- Patient creation from the booking patient search is an in-context nested form, not a router handoff. Prefill the new patient name from the current search text, and only mutate the booking draft after patient save succeeds. Cancelling the patient form or hitting a patient-save error must leave the booking search, selected patient, date, time, duration, and step as they were before creation started.
- Saving or cancelling an edit returns to the Schedule tab without restoring the interrupted details flow. The saved appointment date remains selected.
- While editing, render one draft preview and omit the persisted version of that appointment. Keeping both would duplicate the appointment and make availability suggestions treat it as its own conflict.
- Opening an existing appointment for editing must preserve its saved time exactly. Automatic prefilling remains creation and subsequent date or duration change behavior, not edit initialization behavior.
- Saving an edit updates the existing appointment identity and preserves its status and creation timestamp. Schedule refreshes and selects the saved date before the editor closes.
- Unavailable time blocks are display data - they must never enter appointment availability inputs, nor use appointment availability to determine start time. Suggestions, manual selection, and appointment saving are identical with or without blocks.
- Appointment and block overlaps are valid and require no confirmation. Other doctors can still work while the clinic owner is unavailable.

## Do Not Reintroduce

- Do not turn the prefill preference for empty intervals into a hard availability rule. Visiting doctors make overlapping bookings valid even though they are not the default preference.
- Do not reject a booking because it starts during or extends across the clinic break. Exceptional scheduling must remain possible even though automatic prefilling avoids the break.
