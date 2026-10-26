# Date Strip Architecture

This document captures the deliberate constraints an agent is likely to break if it edits the horizontal date strip without context.

## Invariants

- The date strip selects dates only. It must not own appointments, timeline filtering, or schedule loading.
- Week pages follow the user's active calendar. Do not hard-code a Sunday or Monday week start unless product requirements explicitly change.
- Week boundaries should come from `Calendar.dateInterval(of: .weekOfYear, for:)` so locale, calendar, and time-zone rules stay centralized in Foundation.
- Displayed and selected dates should be normalized to the calendar start of day. Compare day identity with calendar APIs, not raw `Date` equality.
- A single completed swipe may advance at most one calendar week. If the strip uses a three-page paging window, commit the selected page after scrolling becomes idle before recentering.
- When today is not selected, all its text uses the accent color at full opacity. When today is selected, its text is white by default.
- The selected date uses interactive Liquid Glass with the existing continuous rounded rectangle shape and corner radius. Tint the glass with the accent color at full opacity only when today is selected. Color lab can change the selected-today text to black and set the tint opacity. Both values are separate from the Accent control's opacity. Unselected dates have no glass effect.
- Within each week, keep one glass view alive and use matched geometry to move it between date positions. Replacing a separate glass view in each cell can fade the selection out and in. Keep this animation inside the week page so it does not animate paging or recentering.
- Do not clip the date strip scroll view to its bounds. The glass shadow extends below the strip and needs to remain visible above the timeline.
- External day-navigation controls, such as a paged schedule, may drive `selectedDate`. The strip must follow those changes across week boundaries instead of treating its own scroll state as authoritative.

## Do Not Reintroduce

- A rolling seven-day window centered on the selected date; it makes paging feel detached from calendar weeks and breaks user expectations around week boundaries.
- Manual weekday-offset math for week starts; it is easy to get wrong across locales and calendar settings.
- Raw `Date == Date` checks for selected or today state; equal instants are not the same as same calendar day.
- `onTapGesture` for date selection; it loses button semantics and makes accessibility easier to regress.
- Recenter the three-page paging window while the scroll view is still decelerating; fast swipes can otherwise apply the same gesture momentum to more than one week.

## Edge Cases

- If an external owner sets `selectedDate` outside the visible week, the strip should move to that date's calendar week.
- Locale or calendar changes can move week boundaries. Keep date math injectable so tests can cover fixed calendars while production follows the user's settings.
