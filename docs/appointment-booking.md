# Appointment booking

## Suggestions are not restrictions

Allow booking over appointments, breaks, and unavailable time: a visiting dentist
can work while the owner is busy or away. Suggest free working hours because the
clinic usually has one dentist, but do not make this a save restriction.

Suggest a time only when a new session starts. Opening a saved booking, changing
the date, or reloading the schedule must preserve the chosen clock time and
duration so suggestions cannot move the doctor's booking.

## Patient selection

Recency uses past appointments and patient creation. Patient edits and future
bookings must not displace patients who need follow-up.

Creating a patient within booking must preserve the booking draft on cancel or
failure. Other entry points follow the [routing policy](routing.md).

## Schedule context

Keep time selection on the full schedule so the doctor can check placement.
Appointments and unavailable time share the
[direct editing rules](timeline.md#direct-editing).

## Shared creation

Changing draft type preserves the chosen interval and must not change saved data.
Closing the fields keeps the draft. Follow the
[timeline save rules](timeline.md#direct-editing) so the doctor can check placement
before saving.
