# Schedule widgets

Follow the [shared database rules](persistence.md#shared-database-access). Simulator
builds still need signing to preserve the App Group entitlement.

Widgets are snapshots. Refresh for committed schedule changes and time passing so
ended items and yesterday's sections disappear even without a clinic edit.

## Upcoming Schedule (Large)

Show consecutive dates from today, including empty days. Only the final visible
day may omit items and show an overflow count; later work must not displace earlier
work and give a false view of what comes next.

Appointments and unavailable time share capacity and overflow counts.

## Daily Timeline (Extra Large Portrait)

Show all non-cancelled items for one clinic day in proportional timeline form so
the entire day fits without scrolling. Step consecutive calendar days backward and
forward, including Sundays, and return to today automatically after 15 minutes of
inactivity or at clinic midnight so a browsed day cannot linger as today.

When an item starts inside the 1:00–4:00 PM break, expand the break and trim empty
outer hours (`9–10 AM`, `8–9 PM` when no item or current time falls in them) to
keep short cards legible. Pre-generate Now-marker entries on today instead of
scheduling per-minute reloads.
