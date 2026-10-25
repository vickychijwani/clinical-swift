# Timeline Overlap Handling

## Summary

Implement overlap-aware appointment layout in the pure `TimelineLayoutEngine`, keeping `TimelineSegment` as a renderer of engine output. Support up to 3 simultaneous overlapping appointments by splitting the available appointment content width into deterministic columns. Preserve existing vertical time math and break-agnostic timeline invariants.

## Key Changes

- Update `TimelineLayoutEngine.layout(appointments:)` to detect overlap groups using half-open intervals: appointments overlap only when `next.start < current.end`; back-to-back appointments where `end == start` do not overlap.
- Within each overlap group, assign appointments to the first reusable column whose previous appointment has ended, with stable ordering by start time, then end time, then ID.
- Compute each group’s column count from the maximum simultaneous overlap in that group, capped by the assumed product invariant of 3. Card width becomes `(contentWidth - interColumnSpacing * (columns - 1)) / columns`.
- Add a small metric for overlap column spacing, e.g. `overlapColumnSpacing: CGFloat = 4`, so adjacent overlapping cards have a visible divider without changing the time column or hour grid.
- Keep `TimelineSegment.swift` behavior minimal: continue creating the engine and rendering `AppointmentCard` from each returned `rect`; no overlap calculations in the SwiftUI view.
- Adjust `AppointmentCard.swift` text behavior so the time never truncates: give the time text fixed horizontal size and higher layout priority. Patient names stay single-line and are clipped at the trailing card edge without ellipsis by constraining and clipping the name text instead of using `.truncationMode(.tail)`.
- Add overlapping sample appointments in the existing preview/sample path so 2-column and 3-column cases are visible during SwiftUI inspection.
- Update `docs/timeline.md` with a short invariant: overlap layout is segment-local, break-agnostic, supports up to 3 simultaneous appointments, and must not truncate appointment time text.

## Tests

- Add `TimelineLayoutTests.swift` using Swift Testing for the pure layout engine.
- Cover full-width layout for non-overlapping appointments.
- Cover two appointments with the same start time splitting into two columns.
- Cover three simultaneous appointments splitting into three columns.
- Cover staggered overlaps, e.g. A overlaps B, B overlaps C, A does not overlap C, reusing columns while preserving the group’s column width.
- Cover back-to-back appointments where one ends exactly when another starts; they should not split width.
- Verify vertical `y` and `height` calculations remain unchanged from the current duration/start-time math.

## Assumptions

- The product invariant is at most 3 simultaneous overlapping appointments; the implementation does not need a special UI for 4+ overlaps.
- Equal-width columns are preferred over horizontal stacking/offset overlays because they keep all overlapping appointments readable and tappable.
- Patient names may clip without ellipsis; time text must remain fully visible even when the card is narrow.
- No third-party dependency, UIKit bridge, or UI test is needed for this change.
