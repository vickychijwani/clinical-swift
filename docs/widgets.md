# Schedule widgets

Widgets are read-only clients of the app database. The shared access and restore
constraints are in [persistence](persistence.md#shared-database-access).
Keep simulator signing enabled: without the App Group entitlement, even a simulator
build cannot access that database.

Widget entries are snapshots. Reloads must query current data, and committed
schedule changes must request reloads at the database boundary. Calls scattered
among save actions miss writes from other paths. Time-based refresh uses the next
eligible item's end or local midnight so ended items and yesterday's sections do
not remain visible merely because no data changed.

Dates form a consecutive sequence starting today. Do not skip an empty earlier
date to fill the widget with later work. All earlier visible sections must be
complete; only the final visible section may show an overflow count. Otherwise a
later day can displace earlier work and give a false view of what comes next.

Appointments and unavailable time compete for the same space and overflow count.
Capacity is planned before rendering so the widget can fit its fixed size without
views making separate decisions about which work to hide.
