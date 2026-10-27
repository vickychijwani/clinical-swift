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

Late editor completions must identify the router session they belong to before
changing presentation or date selection. An editor model's identity is not proof
that its sheet is still current.

Appointment details must agree with the selected Schedule day before they appear.
Keep the sheet neutral while resolving the record and aligning the schedule.
Enforce this at the route boundary so every entry point gets the same behavior.
Changing the day directly dismisses the details flow rather than showing details
for one day over another day's schedule.
