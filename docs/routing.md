# Presentation and routing

One owner controls app-level presentation and details history across tabs,
widgets, and links. Every entry point must use the same interruption and date rules.

An accepted app-level action replaces the current flow and its temporary state.
Keep only the newest request; never resume an interrupted flow. Internal details
navigation keeps history; an external link starts new history. Settings opens on
device shake and must not replace an active presentation because an accidental
shake could discard an editor.

Closing creation fields does not end the timeline draft. A new app-level action
still replaces it. See [shared creation](appointment-booking.md#shared-creation).

Late saves, record loads, and dismissal callbacks must not change a newer flow or
its selected date.

App-owned flows share one tray. Child steps preserve their parent flow. Contacts
and SMS use native presentation.

Completion payment drafts belong to one appointment-details visit. Back keeps the
draft; leaving the visit discards it. A late payment save must not close another visit.

Appointment details must match the selected Schedule day before they appear.
Selecting another day dismisses details so they cannot appear over the wrong day.
