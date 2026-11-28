# Presentation and routing

One owner controls app-level presentation and details history across tabs,
widgets, and links. Every entry point must use the same interruption and date rules.

An accepted app-level action replaces the current flow and its temporary state.
Keep only the newest request; never resume an interrupted flow. Internal details
navigation keeps history; an external link starts new history. Settings must not
replace an active presentation because an accidental device shake could discard
an editor.

Closing schedule-editor fields does not end the timeline draft. A new app-level
action still replaces it. See [direct editing](timeline.md#direct-editing) and
[shared creation](appointment-booking.md#shared-creation).

Late saves, record loads, and dismissal callbacks must not change a newer flow or
its selected date.

Completion payment drafts belong to one appointment-details visit. Back keeps the
draft; leaving the visit (closing the tray or swiping to another appointment) discards
it without confirmation. A late payment save must not close another visit.

Appointment details must match the selected Schedule day before they appear.
Selecting another day dismisses details so they cannot appear over the wrong day.
Swiping root appointment details switches among scheduled and completed appointments
on that same day in place and never crosses dates.
