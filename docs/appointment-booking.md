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
- Appointment details fit the sheet to their content so the schedule remains visible. Only this step allows interaction with the schedule behind the sheet.
- The booking sheet is not manually resizable or swipe-dismissible. Explicit toolbar actions keep step changes and discard confirmation intentional.
- Creating and editing share one scheduling flow. Edit mode starts on appointment details because rescheduling is the common path, while Back still permits changing the patient.
- Appointment editing is coordinated by the Schedule tab. Entry points from a details flow suspend that presentation and its originating tab, dismiss it, and present the editor only after dismissal so sheets never compete for presentation.
- Starting a booking from patient details follows the same Schedule-owned handoff, with that patient preselected. Saving or cancelling restores the suspended details route, navigation history, and originating tab.
- Saving or cancelling an edit restores the suspended details root and navigation history on its originating tab. Scroll position and sheet detent are transient and return to their normal defaults.
- While editing, render one draft preview and omit the persisted version of that appointment. Keeping both would duplicate the appointment and make availability suggestions treat it as its own conflict.
- Opening an existing appointment for editing must preserve its saved time exactly. Automatic prefilling remains creation and subsequent date or duration change behavior, not edit initialization behavior.
- Saving an edit updates the existing appointment identity and preserves its status and creation timestamp. Schedule refreshes the saved date before the suspended details presentation returns.

## Do Not Reintroduce

- Do not turn the prefill preference for empty intervals into a hard availability rule. Visiting doctors make overlapping bookings valid even though they are not the default preference.
- Do not reject a booking because it starts during or extends across the clinic break. Exceptional scheduling must remain possible even though automatic prefilling avoids the break.
