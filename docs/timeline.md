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

During a drag, break expansion waits for a hold over the compact break. Scale
changes must correct the scroll position so the card stays under the finger. Keep
enough scroll range for that correction, and defer separate draft-reveal scrolling
until the drag ends; competing scroll requests would move the card away from the
touch.

The break is a display preference, not a schedule item or a booking restriction.
See [booking rules](appointment-booking.md).

Time text takes priority over names in narrow overlap columns: the doctor must
still be able to read when an appointment starts.

## Direct editing

Appointment and unavailable-time edits stay in one unsaved draft across gestures
and date changes. Only Done saves these changes; a failed save keeps the draft for
retry. This lets the doctor try positions across days without changing stored
data at each release. The session owns gesture, sheet, save, and error state.
Only its active domain draft is rendered or saved; a second timeline save path
could bypass validation.

Hide the stored version of the edited item on every date page until the session
ends. Showing both versions would make one item appear to occupy two slots when
its draft moves to another day.

A timeline hold starts shared creation even over an existing card. Occupied time
does not make booking invalid. Open the [creation sheet](appointment-booking.md#shared-creation)
after the first drag ends so presentation does not interrupt that gesture.

## Navigation

Keep the horizontal pager's rendered range and the loaded schedule range aligned.
Fast successive swipes can reach beyond the adjacent day before the first animation
ends; loading only adjacent days can expose an empty day that actually has bookings.
