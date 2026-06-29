# Timeline Architecture

This document captures the deliberate constraints an agent is likely to break if it edits the timeline without context.

## Invariants

- `TimelineScale` is the sole source of vertical coordinates. Appointment cards, hour markers, the break background, the now marker, clipped previews, and programmatic scrolling must all use the same scale value.
- The break has two cohesive presentations. It is normally compressed into a compact row; it expands to the normal minute scale when a visible appointment starts within the half-open break range.
- Expansion is based on appointment start time, not interval intersection. An appointment that begins before the break and crosses into it stays on the compact scale so the timeline does not expand unexpectedly.
- Compact break minutes map proportionally into the compact row. Do not collapse every break time onto one coordinate because crossing appointments still need a meaningful height.
- `TimelineLayoutEngine` may use `TimelineScale`, but it must not contain break-specific branches. The scale owns discontinuity policy while the engine owns appointment overlap columns and rectangles.
- `Bitehaus` is the single source of truth for opening, closing, and break boundaries. `Timeline` and `TimelineScale` must read those values directly so rendering and scrolling cannot drift onto different schedules.
- `TimelineBreakView` is presentational only. In compact mode it shows the striped break label; in expanded mode it keeps the striped background and accessibility meaning but removes visible break text.
- Up to three simultaneous appointments may split the content width. Overlap grouping uses actual appointment times even when the break is compact.
- Appointment time text must remain visible in narrow overlap columns. Patient names may clip at the trailing card edge because the time is the non-negotiable scheduling cue.
- The now marker is presentation-only and must not affect appointment layout, hit testing, scrolling, or accessibility focus.
- The now marker should update approximately once per minute. Minute-level accuracy is enough for this scale and avoids unnecessary redraws or timer work.
- Hide the now marker during a compact break because that time is not displayed at full scale; show it normally when the break expands.
- Use `TimeOfDay` for clinic-level schedule boundaries such as opening, closing, and break times. Use `Date` for appointment instances on a specific day.
- Appointment booking may render a draft appointment in the full schedule for context, but the display timeline is not the time editor. Keep draft time changes in the booking controls until a dedicated interaction model exists.
- While a booking draft is active, appointment-card interactions should be disabled without disabling timeline scrolling or date-strip selection. This prevents accidental navigation when appointment-card tap actions are added.
- Booking-mode timeline scroll clearance must stay tied to the measured compact booking sheet height. If details content changes the compact detent, update the schedule's bottom scroll clearance with the same measured value so the lower timeline can still scroll above the sheet.
- The booking sheet is intentionally phased: patient selection can use a large sheet for search results, then appointment details should return to the compact sheet so the timeline regains priority as the scheduling preview.
- In booking mode, keep the date strip outside the timeline scroll view. Date selection must remain pinned while the user scrolls the day around the draft appointment.
- Do not enable swipe-to-dismiss on the booking sheet. It competes with timeline scrolling behind the sheet; use explicit toolbar actions so discard confirmation remains intentional.
- If date, duration, time selection, or availability reconciliation moves the draft appointment, request a timeline scroll to reveal the new preview position. Manual timeline browsing should be the only way the draft card goes off-screen.

## Do Not Reintroduce

- Parallel coordinate helpers like `compressedY(for:)`; they allow rendering and scrolling to disagree with `TimelineScale`.
- A static schedule scale; break presentation depends on the visible scheduled and draft appointments.
- Segment-based appointment filtering or layout; it drops starts inside the break and prevents cross-break overlap grouping.
- Break-aware branches inside `TimelineLayoutEngine`; keep the break policy encapsulated by `TimelineScale`.
- Treating the break as a fake appointment; it has different semantics, interaction, accessibility, and validation rules.
- Embedding a clipped timeline inside the booking sheet; it hides too much of the day and duplicates the schedule's context role.

## Edge Cases

- Appointments during or overlapping the break are valid schedule data. Timeline presentation must not be treated as booking validation.
- A start exactly at break start expands the break; a start exactly at break end does not.
- The draft appointment participates in break expansion so booking preview coordinates match the saved result.
- If the product later needs multiple breaks or arbitrary unavailable ranges, extend `TimelineScale` to model those discontinuities instead of adding coordinate branches to its consumers.
