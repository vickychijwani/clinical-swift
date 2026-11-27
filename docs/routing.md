# Presentation and routing

One owner controls app-level presentation and details history across tabs,
widgets, and links so every entry point uses the same interruption and date
rules.

An accepted app-level action replaces the current flow and its temporary state;
never queue or resume an interrupted flow. Internal details navigation keeps
history; an external link starts new history. Settings opens on device shake and
must not replace an active presentation because an accidental shake could
discard an editor.

Late saves, record loads, and dismissal callbacks must not change a newer flow
or its selected date.

Completion payment drafts are discarded without confirmation when leaving the
appointment-details visit, unlike standalone forms.

Appointment details must match the selected Schedule day before they appear;
selecting another day dismisses details so they cannot appear over the wrong
day.
