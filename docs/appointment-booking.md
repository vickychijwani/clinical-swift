# Appointment booking

## Suggestions are not restrictions

Overlapping appointments, clinic breaks, and unavailable-time blocks do not prevent
booking. A visiting dentist can work while the clinic owner is busy or away. Time
suggestions prefer free working hours because the clinic usually has one dentist;
that preference must not become a save-time restriction.

Opening an appointment for editing preserves its saved time. Applying creation-time
suggestions here could silently move an appointment before the doctor changes it.

## Patient selection

Recency uses past appointments and patient creation, not patient edits or future
bookings. This puts follow-up patients near the top without letting distant
bookings dominate the list.

Creating a patient from booking stays within that booking. Cancel or failure must
leave the draft intact; it is not an app-level interruption. Other entry points
follow the [routing policy](routing.md).

## Schedule context

The full schedule stays visible during time selection so the doctor can place the
appointment in context. The booking sheet uses explicit dismissal actions because
swipe dismissal competes with scrolling the schedule behind it.
