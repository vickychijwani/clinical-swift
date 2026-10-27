# Schedule timeline

## Breaks and coordinates

Break compression belongs to one time scale shared by layout, drawing, and scrolling.
Separate coordinate calculations can put the card, its hit area, and its scroll
position at different times. Overlap groups still use real time, not compressed
coordinates.

A break expands when an item starts inside it. An item that starts before the break
and crosses it stays on the compact scale so a long appointment does not expand
the day unexpectedly. Compact break minutes retain proportional height; collapsing
them to one point would give crossing items misleading durations. Drafts use the
same scale so previews match saved items.

The break is a display preference, not a schedule item or a booking restriction.
See [booking rules](appointment-booking.md).

Time text takes priority over names in narrow overlap columns: the doctor must
still be able to read when an appointment starts.

## Navigation

Keep the horizontal pager's rendered range and the loaded schedule range aligned.
Fast successive swipes can reach beyond the adjacent day before the first animation
ends; loading only adjacent days can expose an empty day that actually has bookings.
