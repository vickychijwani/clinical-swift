# Timeline Architecture

This document captures the deliberate constraints an agent is likely to break if it edits the timeline without context.

## Invariants

- A clinic break is a structural discontinuity, not compressed time inside one global coordinate system.
- Timeline segments are continuous. Inside a segment, `y` position must remain simple minutes-from-segment-start math.
- `TimelineLayoutEngine` must stay break-agnostic. It should not know about break blocks, collapsed heights, hidden hour labels, or discontinuity rules.
- Hour markers and appointment cards in a segment must use the same start and end boundaries.
- `TimelineBreakView` is presentational only. It should render the compact break row, not influence appointment layout.
- Appointment overlap layout is segment-local and break-agnostic. Up to three simultaneous appointments may split the segment content width, but vertical position must still come from simple minutes-from-segment-start math.
- Appointment time text must remain visible in narrow overlap columns. Patient names may clip at the trailing card edge because the time is the non-negotiable scheduling cue.
- The now marker is presentation-only and must not affect appointment layout, hit testing, scrolling, or accessibility focus.
- The now marker should update approximately once per minute. Minute-level accuracy is enough for this scale and avoids unnecessary redraws or timer work.
- Use `TimeOfDay` for clinic-level schedule boundaries such as opening, closing, and break times. Use `Date` for appointment instances on a specific day.
- Booking time selection is continuous across the clinic break. Break starts stay selectable but appear advisory; this must not weaken the display timeline's structural-break model.

## Do Not Reintroduce

- Global helpers like `compressedY(for:)`; they make every timeline feature depend on break-specific coordinate rules.
- `collapsedAmount` or total-height correction logic in `Timeline`; height should fall out of stacked segment heights plus the fixed break row.
- Break-aware appointment layout inside `TimelineLayoutEngine`; that engine is deliberately reusable for any continuous segment.
- Hour-grid filtering to hide labels that fall inside a break; segment boundaries should prevent those labels from being generated.
- Treating the break as a fake appointment; it has different semantics, interaction, accessibility, and validation rules.

## Edge Cases

- Appointments overlapping the break may be created as exceptional bookings. The display timeline must keep them out of segment layout until that flow explicitly supports rendering them; do not silently clip, split, or compress them inside `TimelineSegment`.
- If the product later needs multiple breaks or arbitrary unavailable ranges, introduce a dedicated time-scale abstraction, such as `TimelineScale`, that owns coordinate mapping in one place.
