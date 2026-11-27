# Schedule

## Timeline and breaks

Drawing, touch handling, and scrolling must agree on time, including compressed
breaks. Determine overlaps from real time, not display coordinates.

A break expands for items that start inside it, not those that only cross it;
long appointments must not expand the day unexpectedly. Compressed minutes keep
proportional height so crossing items do not show misleading durations. Drafts
and saved items use the same scale.

During a drag, scale changes and scrolling must keep the card under the finger.
In narrow overlap layouts, keep start times readable before patient names.

Breaks are display preferences, not save restrictions.

## Date strip

Pages follow calendar weeks in the [clinic calendar](../AGENTS.md#architecture).

The schedule owns the selected day. The strip follows other navigation across
week boundaries; scrolling must not create a separate selection.

When day indicators are enabled in Settings, each date shows committed
scheduled and completed appointments split into morning and evening shifts,
ignoring cancelled appointments, unavailable time, drafts, and break hours
(1:00–4:00 PM). Keep the previous, current, and next calendar weeks loaded so
week swipes do not flash empty indicators.

## Direct editing and creation

Keep time selection on the full schedule so the doctor can check placement.
Appointment and unavailable-time drafts survive gestures and date changes. Only
Done saves; failure keeps the draft for retry. Confirm before Cancel discards
it. The doctor must be able to try positions across days without changing saved
data.

The first touch determines whether a hold moves an item or starts creation. A
new booking can then move into occupied time. Present fields after release so
they do not interrupt the drag.

Changing draft type preserves the chosen interval and must not change saved
data. Closing the fields keeps the draft so the doctor can check placement
before saving.

## Booking suggestions and patient selection

Allow booking over appointments, breaks, and unavailable time: a visiting
dentist can work while the owner is busy or away. Suggest free working hours
because the clinic usually has one dentist, but do not make this a save
restriction.

Suggest a time only when a new session starts. Opening a saved booking, changing
the date, or reloading the schedule must preserve the chosen clock time and
duration so suggestions cannot move the doctor's booking.

Recency uses past appointments and patient creation. Patient edits and future
bookings must not displace patients who need follow-up.

Creating a patient within booking must preserve the booking draft on cancel or
failure. Other entry points follow the [routing policy](routing.md).
