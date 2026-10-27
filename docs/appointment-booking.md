# Appointment booking

## Suggestions are not restrictions

Overlapping appointments, clinic breaks, and unavailable-time blocks do not prevent
booking. A visiting dentist can work while the clinic owner is busy or away. Time
suggestions prefer free working hours because the clinic usually has one dentist;
that preference must not become a save-time restriction.

Opening an appointment for editing preserves its saved time. Once timeline editing
starts, date changes preserve the chosen clock time and duration, and schedule
reloads do not apply suggestions. Otherwise, automatic prefilling could silently
move an appointment away from the doctor's chosen time.

## Patient selection

Recency uses past appointments and patient creation, not patient edits or future
bookings. This puts follow-up patients near the top without letting distant
bookings dominate the list.

Creating a patient from booking stays within that booking. Cancel or failure must
leave the draft intact; it is not an app-level interruption. Other entry points
follow the [routing policy](routing.md).

## Schedule context

Time selection stays on the full schedule so the doctor can place the appointment
in context. Appointments and unavailable time follow the same
[direct editing rules](timeline.md#direct-editing).
