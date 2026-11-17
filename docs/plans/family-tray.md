# Family-style tray motion pilot

Status: pilot implemented. Physical-device motion acceptance is pending.

Manual drag-to-resize is deferred at the user's request. Header swipe dismissal
remains in scope. Debug launches use `--details-native` for the comparison sheet
and `--details-medium` to start either version at medium.

## Agreed scope

Replace the native presentation of the existing details flow for one trial:
Appointment Details → Patient Details → Back. Faster opening and closing are
first priority. Continuous height changes are second priority.

Keep the current sheet shape, visual style, background behavior, and detent
heights. Support Close, swipe down, and tap outside. Use the current details
heights: 280 points and medium for details; 400 points for appointment completion.
Match the native detents' visible bounds, including safe-area treatment. A medium
native detent must not be assumed to equal half of the full screen height.

Build new motion and sizing code. Do not copy or extend `FittedSheetModifier`.
Do not add content fitting, force different heights between routes, or migrate
other sheet types in this trial.

## Reference motion analysis

Source: [Family Values](https://benji.org/family-values), particularly the original
[wallet editing clip](https://benji.org/media/family-values/02.mp4),
[options clip](https://benji.org/media/family-values/01.mp4), and
[amount selection clip](https://benji.org/media/family-values/13.mp4).
The article gives design principles, but does not publish animation constants.

The following measurements come from the MP4 files at their encoded speed. The
files are 1180 × 2556 pixels at 60 fps. I tracked the white tray's top edge across
frames and inspected frame sequences. These are estimates of visible geometry,
not measurements of touch latency or proof of Family's animation implementation.
Allow about one or two frames of uncertainty. Compression, repeated frames, and
the edge threshold limit precision.

| Motion | Observed timing | Motion character |
| --- | --- | --- |
| Open wallet details, clip 02, around 0.93 s | Most travel in about 100–150 ms; near rest in about 180–250 ms | Very fast initial rise, then a short slowing tail |
| Close wallet editor, clip 02, around 9.95 s | About 100–130 ms until hidden | Exit accelerates out; much shorter than entry |
| Options → Private Key, clip 01, frames 25–46 | 50% of height change by 100 ms; 90% by 183 ms; 99% by 250 ms | Brief acceleration, then strong deceleration |
| Private Key → Options, clip 01, frames 97–119 | 50% by 83 ms; 90% by 150 ms; 99% by 250 ms | Similar time scale for contraction |
| Choose Amount → Custom Amount, clip 13, frames 288–308 | 50% by 83 ms; 90% by 150 ms; 99% by 217 ms | Large expansion with a short tail |
| Custom Amount → Review Details, clip 13, frames 391–410 | 50% by 83 ms; 90% by 167 ms; 99% by 233 ms | Smaller contraction with similar timing |

Height changes appear to settle in roughly 250–320 ms. The speed depends on the
travel distance: the two larger sampled morphs peak at about 1.8–2.1 screen
heights per second; the smaller contraction peaks at about 0.8. The similar time
to reach 90% suggests a common time scale rather than a fixed points-per-second
speed. This is an inference from these samples.

There is no obvious bounce. The wallet-details entrance and the warning entrance
in [clip 03](https://benji.org/media/family-values/03.mp4) pass their final top edge
by about 2–4 video pixels, then return. This small movement could reflect subtle
overshoot or recording/layout effects. It does not establish that Family uses a
spring. Start the trial with zero visible bounce.

The morph keeps a continuous tray surface and bottom position while its top edge
moves. Outgoing and incoming content overlap during the size change; the system
does not close one tray and open another. Content remains readable instead of
stretching vertically with the surface. Rounded corners remain visually stable.
The article also describes changing height to signal progression. We will keep
our existing detents, so equal-height routes will remain equal in height.

## Proposed motion

Use separate settings for entry, exit, and height changes. Do not apply one broad
animation to the complete app view tree.

| Property | Initial setting to test | Acceptance target |
| --- | --- | --- |
| Entry position | Zero-bounce spring, perceptual duration 0.24 s | Most travel within 150 ms; near rest within 250 ms |
| Exit position | `.easeIn(duration: 0.13)` | Hidden within about 100–150 ms |
| Height change | Zero-bounce spring, perceptual duration 0.28 s | 90% travel within 150–190 ms; visually settled within 320 ms |
| Dim layer | Start with entry/exit, no delay; fade within their duration | No flash or dark pause before the tray moves |
| Route content | Keep native details navigation in the first trial | No dismiss/reopen between internal routes; no stretched text |

These are proposed SwiftUI starting values, not recovered Family constants.
Measure the rendered result and tune it against the reference. A spring can have
zero bounce. Apple's [spring API](https://developer.apple.com/documentation/swiftui/animation/spring(duration:bounce:blendduration:))
uses perceptual duration, so its duration value is not an exact removal deadline.
Do not choose `.snappy` by its name: Apple's
[animation guide](https://developer.apple.com/videos/play/wwdc2023/10156/)
states that this preset has some bounce.

## Implementation sequence

### 1. Record the current behavior

Use synthetic data and the same simulator/device for both versions. Record the
native sheet before changing presentation. Capture:

- Open, Close, tap outside, and swipe dismissal at each available detent.
- Appointment → Patient → Back, including the current selected detent behavior.
- Drag from 280 points to medium and back. Check how scrolling and resizing share
  the gesture because the current flow uses `.presentationContentInteraction(.resizes)`.
- Completion at 400 points, keyboard appearance, Back, and discard confirmation.
- Sheet bounds, corner shape, dim layer, background interaction, and any native
  movement of the underlying app.

Use this recording to resolve platform details. Preserve current background
behavior; add no new background interaction. Record tap-outside behavior because
its requested dismissal must use the same discard rules as Close.

### 2. Build one SwiftUI presentation host

Add a small host at the app root for details only. It owns the dim layer, tray
surface, vertical position, detent selection, and drag state. Use SwiftUI and
public APIs. Keep the existing content and native navigation controls where
possible. Other presentation types keep their native sheets.

Use explicit height targets for this trial. Build a new detent resolver from the
available container, safe areas, and keyboard space. Validate its visible bounds
against the baseline. Do not measure a `NavigationStack` or `ScrollView` to infer
content height. Do not introduce a hidden copy of a live screen for measurement.

Keep one tray surface for the full details session. Animate height from its
current rendered value to the next target with the bottom anchored. The first
frame must use the resolved initial detent, without an intermediate medium
height or visible correction. During keyboard movement, keep the focused field
and action reachable and avoid applying a second conflicting keyboard animation.

Keep the current native `NavigationStack` transition in this first trial. Prove
that it can coexist with the custom height motion. Exact Family content morphs,
custom headers, and a replacement navigation stack are outside this trial. If
native navigation prevents acceptable height motion, report the limitation before
expanding scope.

### 3. Connect it to the router

`Router.activePresentation` remains the source of presentation intent. The host
must not create a second route history or revive a discarded flow.

The current integration relies on native `onAppear`, `onDismiss`, and environment
`dismiss`. An overlay does not provide equivalent sheet dismissal automatically.
Add an explicit dismissal action for hosted content and route all supported
ways to close through one policy.

Retain the outgoing presentation's display state until its exit finishes, even
when the router has cleared its active intent. Its content must not disappear
before its surface. Keep retained state separate from authority to perform an
action. Session and visit checks must still reject late saves and route updates.

Report presentation appearance and dismissal once for the matching session. Use
animation completion and session validation, not a sleep with the expected
animation duration. An old completion must never clear a newer presentation.
Keep only the newest replacement request during dismissal. Wait for the custom
tray to finish before handing off to a native editor, message sheet, or booking
flow. Remove the native `.sheet` host for details when the custom host is active.

Completion is already inside the details sheet. It must keep working in the
pilot, including draft retention on Back, discard confirmation, disabled dismissal
during save, keyboard handling, and session/visit ownership checks. Read-only
details screens cannot be used to bypass those requirements.

### 4. Add direct manipulation

During a drag, follow the finger without a time-based animation. Preserve the
current detent collapse/expand behavior. Use displacement and release velocity
to decide whether to change detent, return, or dismiss. Animate the release from
the current position, without a jump.

Arbitrate scrolling and dismissal explicitly. Start with header dragging; allow
content dragging only where it preserves native scroll and resize behavior. A
scroll gesture must not accidentally close the tray. Close, swipe, and tap outside
must obey the same unsaved-change and save-in-progress rules.

A new request during entry or a height change must update from the current visual
state. Do not queue taps until an animation ends. Clear drag offsets and reject
stale completion callbacks when the session changes.

## Validation and decision

Add a temporary Debug launch option to choose native or custom details
presentation before launch. Use the same route, synthetic records, and detents
for both. This is a comparison tool, not a user setting.

Unit-test the new detent resolver and presentation lifecycle. Cover short
containers, keyboard space, cancelled drags, rapid replacement, interrupted
entry/exit, and stale completion callbacks. Extend `RouterTests` and the existing
completion interruption tests where integration changes. Run `make test`.

Use UI tests for behavior that unit tests cannot establish: hit testing, Close,
outside tap, drag/scroll conflict, detent changes, keyboard visibility, native
sheet handoff, and payment discard/save behavior. Extend the current completion
UI tests as needed and use `ElementWaits.swift` for waits. Run `make ui-test`.
Do not use XCTest's animation waits as a timing measurement.

Record repeatable native and custom open/close sequences. Record the tray's top
edge and timestamps for first visible motion, 50%, 90%, near rest, and fully
hidden. Compare them with the ranges above. Separate input-to-first-frame delay
from animation travel time; the reference clips cannot establish input latency.

Review on a physical iPhone at normal speed and slow playback. Check a release
build with Instruments for animation hitches, including long patient histories
and cold data loads. A simulator recording cannot establish 120 Hz performance.
Include the smallest supported phone size and a keyboard-visible completion.

Accept the pilot when opening and closing feel as immediate as the reference,
there is no visible bounce or height jump, height targets match the native
baseline, and all navigation, dismissal, draft, and replacement checks pass.
Review the real details flow with the user before migrating any other sheet.
Keep timing adjustments local and remove the temporary comparison option after
the decision. Update `docs/routing.md` only if the final implementation changes a
documented ownership or lifecycle decision.
