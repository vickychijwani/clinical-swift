# Timeline Architecture

This document captures the deliberate constraints an agent is likely to break if it edits the timeline without context.

## Invariants

- A clinic break is a structural discontinuity, not compressed time inside one global coordinate system.
- Timeline segments are continuous. Inside a segment, `y` position must remain simple minutes-from-segment-start math.
- `TimelineLayoutEngine` must stay break-agnostic. It should not know about break blocks, collapsed heights, hidden hour labels, or discontinuity rules.
- `TimelineScale` owns presentation-level coordinates across the structural break for clipping and programmatic scrolling. Keep this mapping out of `TimelineLayoutEngine` so appointment layout remains segment-local.
- `Bitehaus` is the single source of truth for opening, closing, and break boundaries. `Timeline` and `TimelineScale` must read those values directly so rendering and scrolling cannot drift onto different schedules.
- Hour markers and appointment cards in a segment must use the same start and end boundaries.
- `TimelineBreakView` is presentational only. It should render the compact break row, not influence appointment layout.
- Appointment overlap layout is segment-local and break-agnostic. Up to three simultaneous appointments may split the segment content width, but vertical position must still come from simple minutes-from-segment-start math.
- Appointment time text must remain visible in narrow overlap columns. Patient names may clip at the trailing card edge because the time is the non-negotiable scheduling cue.
- The now marker is presentation-only and must not affect appointment layout, hit testing, scrolling, or accessibility focus.
- The now marker should update approximately once per minute. Minute-level accuracy is enough for this scale and avoids unnecessary redraws or timer work.
- Use `TimeOfDay` for clinic-level schedule boundaries such as opening, closing, and break times. Use `Date` for appointment instances on a specific day.
- Appointment booking may render a draft appointment in the full schedule for context, but the display timeline is not the time editor. Keep draft time changes in the booking controls until a dedicated interaction model exists.
- While a booking draft is active, appointment-card interactions should be disabled without disabling timeline scrolling or date-strip selection. This prevents accidental navigation when appointment-card tap actions are added.
- Booking-mode timeline scroll clearance must stay tied to the measured compact booking sheet height. If details content changes the compact detent, update the schedule's bottom scroll clearance with the same measured value so the lower timeline can still scroll above the sheet.
- The booking sheet is intentionally phased: patient selection can use a large sheet for search results, then appointment details should return to the compact sheet so the timeline regains priority as the scheduling preview.
- In booking mode, keep the date strip outside the timeline scroll view. Date selection must remain pinned while the user scrolls the day around the draft appointment.
- Do not enable swipe-to-dismiss on the booking sheet. It competes with timeline scrolling behind the sheet; use explicit toolbar actions so discard confirmation remains intentional.
- If date, duration, time selection, or availability reconciliation moves the draft appointment, request a timeline scroll to reveal the new preview position. Manual timeline browsing should be the only way the draft card goes off-screen.

## Do Not Reintroduce

- Global helpers like `compressedY(for:)`; they make every timeline feature depend on break-specific coordinate rules.
- `collapsedAmount` or total-height correction logic in `Timeline`; height should fall out of stacked segment heights plus the fixed break row.
- Break-aware appointment layout inside `TimelineLayoutEngine`; that engine is deliberately reusable for any continuous segment.
- Hour-grid filtering to hide labels that fall inside a break; segment boundaries should prevent those labels from being generated.
- Treating the break as a fake appointment; it has different semantics, interaction, accessibility, and validation rules.
- Embedding a clipped timeline inside the booking sheet; it hides too much of the day and duplicates the schedule's context role.

## Edge Cases

- Appointments during or overlapping the break are valid schedule data. Timeline segmentation must not be treated as booking validation.
- If the product later needs multiple breaks or arbitrary unavailable ranges, extend `TimelineScale` to model those discontinuities instead of adding coordinate branches to its consumers.
