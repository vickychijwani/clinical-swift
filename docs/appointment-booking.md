# Appointment Booking Architecture

This document captures the deliberate constraints an agent is likely to break when changing appointment booking.

## Invariants

- Overlapping appointments are valid. The clinic can have multiple doctors attending different patients at the same time, so an existing appointment does not make that interval unavailable.
- Booking during or across the clinic break is valid. The break is a scheduling preference, not unavailable time.
- Automatic time prefilling should prefer an empty interval within the regular working segments because the clinic usually has a single doctor.
- Existing appointments must not restrict manual time selection or saving. Multiple doctors may be available even when the selected interval is occupied.
- Patient selection uses a stable full-height sheet so search results and the keyboard do not resize it.
- Appointment details fit the sheet to their content so the schedule remains visible. Only this step allows interaction with the schedule behind the sheet.
- The booking sheet is not manually resizable or swipe-dismissible. Explicit toolbar actions keep step changes and discard confirmation intentional.
- Creating and editing share one scheduling flow. Edit mode starts on appointment details because rescheduling is the common path, while Back still permits changing the patient.
- Appointment editing is coordinated by the Schedule tab. Entry points from any tab dismiss their details flow before presenting the editor so sheets never compete for presentation.
- While editing, render one draft preview and omit the persisted version of that appointment. Keeping both would duplicate the appointment and make availability suggestions treat it as its own conflict.
- Opening an existing appointment for editing must preserve its saved time exactly. Automatic prefilling remains creation and subsequent date or duration change behavior, not edit initialization behavior.
- Saving an edit updates the existing appointment identity and preserves its status and creation timestamp. After saving or cancelling, remain on the currently selected schedule date rather than reconstructing the originating navigation context.

## Do Not Reintroduce

- Do not turn the prefill preference for empty intervals into a hard availability rule. Visiting doctors make overlapping bookings valid even though they are not the default preference.
- Do not reject a booking because it starts during or extends across the clinic break. Exceptional scheduling must remain possible even though automatic prefilling avoids the break.
