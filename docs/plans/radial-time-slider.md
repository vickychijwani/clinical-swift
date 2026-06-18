# Radial Time Slider

## Summary
Build an original, repo-native `RadialTimeSlider` inspired by the reference component’s configurable range and discrete steps. Use SwiftUI `Canvas` for efficient tick rendering and `.sensoryFeedback(.selection)` for haptics.

## Key Changes
- Add `RadialTimeSlider` under `clinical-swift/widgets/` with:
  - `Binding<TimeOfDay>`, a same-day `ClosedRange<TimeOfDay>`, configurable positive minute step, and cohesive normal/advisory status configuration.
  - A semicircular rotating tick band beneath a fixed accent indicator.
  - Longer hour ticks, shorter step ticks, and muted advisory ticks.
  - A proportional time readout using the repo’s existing text styles, with `Available`/`Break` status styled consistently with secondary captions.
  - Horizontal scrubbing that commits each crossed step and triggers selection haptics.
  - Clamped endpoints with temporary rubber-band displacement and no wrapping.
  - A rounded `.background` card using the booking screen’s existing 18-point shape and semantic colors.
- Keep tick/index/drag calculations in a small pure scale type:
  - Convert between `TimeOfDay`, discrete indices, and angular offsets.
  - Draw only ticks within the visible arc.
  - Clamp incoming and dragged values to representable range values.
- Update appointment booking:
  - Replace the compact `DatePicker` with the radial slider.
  - Configure `9:00 AM...8:30 PM`, five-minute steps, and advisory `1:00 PM..<4:00 PM`.
  - Add a `TimeOfDay` mutation path to `AppointmentBookingDraft`.
  - Preserve the separate duration selector.
- Update booking rules:
  - Add a fixed `Bitehaus` latest-start boundary of `8:30 PM`.
  - Clamp start time independently of duration.
  - Keep the clinic break selectable but visually advisory.
  - Accept any positive duration; reject zero or negative durations.
- Document that the display timeline retains its structural break while booking selection remains continuous.

## Verification
- Unit-test scale generation, snapping, hour ticks, drag direction, and endpoint clamping.
- Update draft tests for fixed latest-start clamping, selectable break starts, duration-independent normalization, and positive-duration validation.
- Add previews for normal, break, and endpoint states.
- Verify scrubbing, haptics, rubber-band recovery, form scrolling, text styling, and light/dark appearance in Simulator.
- Run `make test` and confirm a warning-free build.

## Assumptions
- The control is same-day and non-wrapping.
- Existing appointments do not influence status.
- Break status depends only on the selected start being inside `1:00 PM..<4:00 PM`.
- The radial slider is the sole visible time input.
- Accessibility-specific behavior is deferred without adding placeholder comments.

