# Timeline Architecture

This document captures the deliberate constraints an agent is likely to break if it edits the timeline without context.

## Invariants

- `TimelineScale` is the sole source of vertical coordinates. Appointment cards, hour markers, the break background, the now marker, clipped previews, and programmatic scrolling must all use the same scale value.
- The break has two cohesive presentations. It is normally compressed into a compact row; it expands to the normal minute scale when a visible appointment or block starts within the half-open break range.
- Expansion is based on appointment start time, not interval intersection. An appointment that begins before the break and crosses into it stays on the compact scale so the timeline does not expand unexpectedly.
- Compact break minutes map proportionally into the compact row. Do not collapse every break time onto one coordinate because crossing appointments still need a meaningful height.
- `TimelineLayoutEngine` may use `TimelineScale`, but it must not contain break-specific branches. The scale owns discontinuity policy while the engine owns appointment overlap columns and rectangles.
- `Bitehaus` is the single source of truth for opening, closing, and break boundaries. `Timeline` and `TimelineScale` must read those values directly so rendering and scrolling cannot drift onto different schedules.
- `TimelineBreakView` is presentational only. In compact mode it shows the striped break label; in expanded mode it keeps the striped background and accessibility meaning but removes visible break text.
- Up to three simultaneous schedule items may split the content width. Overlap grouping uses actual times even when the break is compact.
- Appointment time text must remain visible in narrow overlap columns. Patient names may clip at the trailing card edge because the time is the non-negotiable scheduling cue.
- Appointments and unavailable-time blocks share one adaptive card layout. Keep their appearance values together, and apply content opacity only to text and symbols so the surface and border stay visible. Keep status animation and item actions outside the shared layout.
- The now marker is presentation-only and must not affect appointment layout, hit testing, scrolling, or accessibility focus.
- Keep the now marker above every card, including a full-width appointment in direct adjustment mode.
- The now marker should update approximately once per minute. Minute-level accuracy is enough for this scale and avoids unnecessary redraws or timer work.
- Hide the now marker during a compact break because that time is not displayed at full scale; show it normally when the break expands.
- Use `TimeOfDay` for clinic-level schedule boundaries such as opening, closing, and break times. Use `Date` for appointment instances on a specific day.
- New and edited appointments use the same timeline gestures as direct adjustment. The active session owns one unsaved preview.
- Completed appointments remain selectable schedule records but use a persistently muted card treatment so scheduled work retains visual priority. Cancelled appointments never reach timeline layout or rendering.
- While a booking draft is active, only that card accepts drag and duration gestures. Other card actions stay disabled. Timeline scrolling and date selection remain available.
- Appointment booking uses a full-height sheet only for patient selection. Time editing uses the schedule, with no time or duration sheet.
- Direct adjustment needs extra scroll range to keep the card under the finger when the break scale changes. Keep this scroll range for both appointment and unavailable-time editing.
- In booking mode, keep the date strip outside the timeline scroll view. Date selection must remain pinned while the user scrolls the day around the draft appointment.
- Do not enable swipe-to-dismiss on the booking sheet. It competes with timeline scrolling behind the sheet; use explicit toolbar actions so discard confirmation remains intentional.
- Reveal the draft after initial presentation or date selection. Do not issue a separate reveal scroll during a drag; the gesture owns its position and scale correction.
- Horizontal day paging owns date navigation only. Timeline coordinate policy, break expansion, and programmatic vertical scrolling must continue to derive from `TimelineScale` for the day being rendered.
- Horizontal day paging renders and loads beyond the immediately adjacent day so a second swipe can begin before the first page animation commits. Keep the pager radius and schedule query window in sync; otherwise fast swipes can land on an empty placeholder for a day whose appointments have not been loaded yet.
- Never render appointment details for date X over a schedule showing date Y. A visible appointment route must align the Schedule tab and selected day before rendering its details; changing the day directly dismisses the complete details flow instead of leaving contradictory context on screen.

### Invariants for mixed schedule items

- Timeline rendering, scale, and layout accept `TimelineItem` only. Keep tests and previews on this API so they check the same path as the app.
- The timeline reports the selected `TimelineItem` through one callback. Schedule owns the action for each item type. This keeps navigation and editor presentation out of the timeline.
- One active editor session supplies the preview, selected date, and scroll requests. Keep the concrete models separate: only appointments use availability updates, and unavailable-time editors prevent date changes during saving or deletion.

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
- A hold anywhere on the timeline always starts a new appointment booking, including over an appointment or unavailable-time card. Use the touched time as the midpoint of the default duration, snap the resulting start to the nearest 15-minute boundary, then clamp the interval to clinic hours. Later drags use five-minute steps. A quick swipe must remain a scroll, and a normal appointment-card tap opens its details. An unavailable-time card tap starts editing.
- Keep the initial hold and drag attached to the timeline when the new card appears. Open patient selection only after release. Selecting a patient closes the sheet and keeps the same unsaved card, time, and duration active.
- Dragging the active card changes its start time and keeps duration fixed. The bottom handle changes duration and keeps the start fixed. There is no separate start handle. Changes snap to five minutes, with a minimum duration of 15 minutes.
- Release and date selection update the preview only. Done saves all changes; Cancel confirms before discarding them. A save failure keeps the preview for retry. Block gestures, date selection, and repeated saves while saving.
- Mini glass Cancel and prominent Done icon buttons follow the card just below its right edge. They stay enabled during dragging. Done ends the drag and saves, or opens patient selection if needed; Cancel ends the drag before confirming discard. Anchor the discard prompt to Cancel. Keep the bottom-center duration handle clear of these buttons. The navigation toolbar does not own these actions.
- The schedule owns adjustment across date pages. Hide the tab bar and ignore other card taps while it is active. Selecting a date keeps the same time and duration; do not reconcile it against slot suggestions, conflicts, or the break. Hide the stored version on all pages until completion.
- Lay out the selected appointment or unavailable-time block at the full content width, outside the overlap columns, and render its translucent surface above other cards. Keep its identity stable when it enters this layout so the current touch remains attached to the card.
- While an appointment or unavailable-time block is being created or edited, reduce text and symbol opacity on all other cards. Keep their surfaces and borders visible for schedule context. The active card uses a white fill with adjustable opacity so underlying card boundaries remain visible as conflict cues. Keep its text and accent outline at full opacity.
- While the active card or its duration handle is pressed, slightly increase its width and cast a soft shadow. Use a quick spring with no bounce. Keep height and vertical position fixed because they communicate the appointment interval. Apply the effect outside clipping and keep the action buttons outside the transform. Remove the shadow inside the card outline so it cannot darken the translucent fill. Card buttons must not apply system press dimming; the lift owns their press feedback.
- Keep the selected date in the Schedule title during adjustment. The card already shows the patient name, so do not add a separate patient-name control to the toolbar.
- Center the duration grip on the card's bottom edge. Keep its touch area larger than the visible grip so resizing remains easy.
- During a drag, show the time and duration tooltip below the card when its start is within 30 minutes of clinic opening, including the boundary. Align it horizontally with the action buttons, with the tooltip on the left and the buttons on the right. At later start times, show it above the card. Apply this rule to appointments and unavailable time so the tooltip stays inside the timeline at opening.
- Debug builds include a local Card lab switch in Settings. Show its panel only on the main Schedule screen, including direct card adjustment. Hide it on other tabs, pushed destinations, and all sheets, including patient and label selection. Drag its header to place it anywhere in the available space. Values, panel position, and collapsed state persist on this device. Reset restores the checked-in appearance. Controls set white-fill opacity, other-card text and symbol opacity, and the press lift. Release builds use the default appearance and have no activation control.
- During a direct drag, keep the break compact until the moving edge stays over it for 550 ms. Leaving the compact break cancels that wait. After expansion, collapse the break when the moving appointment leaves it, unless another schedule item starts in the break. Use the shared scale for the inverse time mapping and correct the scroll position when the scale changes so the card stays under the finger.
- Unavailable-time creation starts from its toolbar button: open the optional label sheet, then return to the active timeline card. Keep the initial start at clinic opening and the duration at 60 minutes. Back and Continue retain the label and return to the unsaved card; neither action saves. Later drag releases keep the sheet closed. Tapping the active card reopens its label or patient sheet. These sheets disable background interaction and swipe dismissal.
- Tapping an existing unavailable-time card starts direct editing without a label sheet. Its card has the same move, duration, Cancel, and Done controls and press effect as an appointment. Add a confirmed Delete action beside Cancel and Done for saved blocks only. Delete uses the saved block identity even if its unsaved preview has moved.
- Appointment and unavailable-time adjustments share the same time mapping and break-hover rules, but keep their item type and identity. A block must not become an appointment to use the drag controls. Date changes keep clock time and duration; overlaps and break times remain valid.
- Booking and appointment editing select their draft card immediately. Open an existing appointment's editor from details; a hold on its card creates a new booking. Overlaps and break times remain valid.
- If the product later needs multiple breaks or arbitrary unavailable ranges, extend `TimelineScale` to model those discontinuities instead of adding coordinate branches to its consumers.
