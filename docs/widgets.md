# Schedule widgets

Follow the [shared database rules](persistence.md#shared-database-access). Simulator
builds still need signing to preserve the App Group entitlement.

Widgets are snapshots. Refresh for committed schedule changes and time passing so
ended items and yesterday's sections disappear even without a clinic edit.

Show consecutive dates from today, including empty days. Only the final visible
day may omit items and show an overflow count; later work must not displace earlier
work and give a false view of what comes next.

Appointments and unavailable time share capacity and overflow counts.
