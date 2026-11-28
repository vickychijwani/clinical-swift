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

Show one clinic day's active items in proportional timeline form so the entire
day fits without scrolling. Step consecutive calendar days backward and forward,
including Sundays. Request a return to today after 15 minutes of inactivity or
at clinic midnight on WidgetKit's next reload (best-effort, rather than
archiving a fallback Today view on every tap).

Follow the [break expansion rule](timeline.md#breaks-and-coordinates); when the
break expands in the widget, trim empty outer hours so short cards stay legible.
Pre-generate a short rolling window of Now-marker entries on today during
background reloads instead of per-minute reloads or archiving the full day up
front. Keep interactive day-navigation taps to one timeline entry (one day read,
one archived view) so taps stay fast, and keep widget-only intents in
`ClinicalWidget` without manual `reloadTimelines` calls so iOS runs them in the
extension without waking the app or double-reloading.

After changing the Daily Timeline widget, ask the user whether to run on-device
widget performance tests (`make widget-perf-test DEVICE='<name|udid>'`).
