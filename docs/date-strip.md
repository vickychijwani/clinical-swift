# Date Strip Architecture

This document captures the deliberate constraints an agent is likely to break if it edits the horizontal date strip without context.

## Invariants

- The date strip selects dates only. It must not own appointments, timeline filtering, or schedule loading.
- Week pages follow the user's active calendar. Do not hard-code a Sunday or Monday week start unless product requirements explicitly change.
- Week boundaries should come from `Calendar.dateInterval(of: .weekOfYear, for:)` so locale, calendar, and time-zone rules stay centralized in Foundation.
- Displayed and selected dates should be normalized to the calendar start of day. Compare day identity with calendar APIs, not raw `Date` equality.
- A single completed swipe may advance at most one calendar week. If the strip uses a three-page paging window, commit the selected page after scrolling becomes idle before recentering.
- Today styling is independent from selection. When today is visible, both its weekday and date number should use the accent color.

## Do Not Reintroduce

- A rolling seven-day window centered on the selected date; it makes paging feel detached from calendar weeks and breaks user expectations around week boundaries.
- Manual weekday-offset math for week starts; it is easy to get wrong across locales and calendar settings.
- Raw `Date == Date` checks for selected or today state; equal instants are not the same as same calendar day.
- `onTapGesture` for date selection; it loses button semantics and makes accessibility easier to regress.
- Recenter the three-page paging window while the scroll view is still decelerating; fast swipes can otherwise apply the same gesture momentum to more than one week.

## Edge Cases

- If an external owner sets `selectedDate` outside the visible week, the strip should move to that date's calendar week.
- Locale or calendar changes can move week boundaries. Keep date math injectable so tests can cover fixed calendars while production follows the user's settings.
