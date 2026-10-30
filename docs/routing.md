# Presentation and routing

The router owns app-level presentation and details history across tabs, widgets,
and links. Separate presentation owners can try to show competing sheets or apply
different date rules to the same destination.

An accepted app-level action replaces the old presentation and its transient state.
Keep only the newest request while a sheet dismisses. Do not queue actions or
restore an interrupted flow afterward: old state must not compete with the user's
new action. Moving within a details flow preserves its history; an external link
replaces that history with a new root. Settings opens only when no sheet is active,
so it cannot discard an editor.

Generic schedule creation has one router identity across draft type changes.
Closing its shared sheet keeps that session active; a field sheet's visibility
is not the lifetime of a timeline draft. If a new app-level action interrupts
dismissal, the normal replacement policy still applies. See
[shared creation](appointment-booking.md#shared-creation) for its commit boundary.

Late editor completions must identify the router session they belong to before
changing presentation or date selection. An editor model's identity is not proof
that its sheet is still current.

Completion payment drafts belong to one appointment-details visit. Back keeps the
draft; leaving that visit discards it. A payment save must match the active session,
draft instance, and originating path before dismissing details. The session ID
alone is insufficient because an in-place root replacement reuses it.

Appointment details must agree with the selected Schedule day before they appear.
Keep the sheet neutral while resolving the record and aligning the schedule.
Enforce this at the route boundary so every entry point gets the same behavior.
Changing the day directly dismisses the details flow rather than showing details
for one day over another day's schedule.
