# Schedule timeline

## Breaks and coordinates

Drawing, touch handling, and scrolling must agree on time, including compressed
breaks. Determine overlaps from real time, not display coordinates.

A break expands for items that start inside it, not those that only cross it;
long appointments should not expand the day unexpectedly. Compressed minutes keep
proportional height so crossing items do not show misleading durations. Drafts
and saved items use the same scale.

During a drag, scale changes and scrolling must keep the card under the finger.

Breaks are display preferences. See [booking rules](appointment-booking.md) for
overlaps and unavailable time.

In narrow overlap layouts, keep start times readable before patient names.

## Direct editing

Appointment and unavailable-time drafts survive gestures and date changes. Only
Done saves; failure keeps the draft for retry. Confirm before Cancel discards it.
The doctor must be able to try positions across days without changing saved data.

The first touch determines whether a hold moves an item or starts
[creation](appointment-booking.md#shared-creation). A new booking can then move into
occupied time. Present fields after release so they do not interrupt the drag.
