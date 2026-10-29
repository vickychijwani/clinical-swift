---
status: implemented
---

# Shared schedule creation sheet

## Purpose

Use one Schedule toolbar Add button and one timeline hold gesture to start either
an appointment or unavailable time. Put patient selection and optional label entry
in one sheet with a native segmented control.

## Agreed behavior

### Entry points and time placement

- Replace the separate Schedule creation buttons with one toolbar `+` button.
- Use the same creation sheet for the toolbar action and timeline hold.
- Keep time placement on the timeline.
- Start each generic creation session with Appointment selected.
- Keep the current appointment starting interval: a suggested 30-minute slot for
  toolbar creation, or a 30-minute interval placed by the hold gesture. Switching
  to Unavailable Time keeps this interval, even before a manual time adjustment.
- Patient-specific booking stays appointment-only. It starts with that patient and
  goes straight to the timeline, as it does now. Its sheet has no type selector.
- Saved items keep their type. Their edit sheets have no type selector.

### Switching type

- Use a native segmented control with Appointment and Unavailable Time segments.
- Permit segment changes throughout generic unsaved creation. Reopen the shared
  sheet by tapping its draft card.
- Preserve the draft date, start, and duration when its type changes. Do not run
  another time suggestion as a result of a segment change.
- Clear the selected patient and search text when leaving Appointment. Clear the
  label when leaving Unavailable Time. Switching back starts with empty fields.
  These resets do not change the time interval or delete a saved patient record.
- Keep one visible draft card. Change its type and appearance when the segment
  changes. Switching does not write a schedule record.

### Sheet actions and saving

- Selecting a patient returns to the timeline. Unavailable Time has a Continue
  action that returns to the timeline, including when its label is empty.
- Back and swipe-to-close return to the timeline without saving or discarding the
  session. Enable swipe dismissal. Reopening the sheet without a segment change
  keeps the current entries.
- Done on the timeline saves only the active type. An appointment requires a
  patient; if none is selected, Done reopens the sheet on Appointment. Unavailable
  Time does not require a label.
- Cancel on the timeline card uses the existing discard confirmation. A save
  failure keeps the active draft for retry.

## Interaction details

- Put the segmented control above the active segment's fields, outside the patient
  results scroll area. Use one sheet and one navigation container.
- Keep the sheet open when changing segments. Move focus to the visible search or
  label field. Do not carry the other field's focus into the new segment.
- A timeline hold keeps its first drag active. Show the shared sheet only after
  release. Preserve the hold's chosen time when switching to Unavailable Time.
- Keep the existing hold behavior over occupied cards and inside clinic breaks.
  Keep the initial 15-minute snap and later five-minute movement.
- Keep patient creation within the booking. Cancel or failure returns to the same
  Appointment segment and draft. While the patient form is open, the underlying
  segment control cannot be changed.
- Disable type changes during a save. Clear any error for the previous type when
  switching, so it does not appear against the new draft.

## Existing constraints

Follow [booking rules](../appointment-booking.md) for overlaps and time
suggestions, [timeline rules](../timeline.md) for direct editing, and
[routing rules](../routing.md) for session identity and interruptions. These
constraints also apply when the draft type changes.

## Implementation plan

1. **Session and routing.** Refactor `ScheduleEditorSession` to distinguish generic
   creation, patient-specific booking, and saved-item editing. Make generic
   creation independent of draft type in `Router`. Keep the router session ID
   stable across switches. Make type changes observable, with one visible draft
   and one active save operation.
2. **Type transitions.** Copy the current interval into the selected type's draft
   without another suggestion. Clear fields for the type being left. Preserve the
   existing validation and persistence rules. Consolidate shared editor state and
   behavior where that removes duplication; retaining both current editor models
   is not a requirement. Release any gesture state before a switch. Prevent stale
   errors and completions from changing the current session.
3. **Shared sheet.** Replace the type-based sheet selection in `ScheduleView` with
   a shared container. Reuse patient search, patient creation, and label entry from
   `AppointmentBookingView` and `UnavailableTimeEditorView`. Add the segmented
   `Picker` only for generic creation. Use one `NavigationStack`, one close path,
   explicit focus changes, and swipe dismissal that retains the session.
4. **Entry points and timeline.** Remove the separate Unavailable Time toolbar
   button. Connect Add and the existing hold gesture to generic creation. Keep the
   hold's first drag and release sequence. Use the active type for preview,
   adjustment, sheet reopening, and Done. Preserve saved-item editing and
   patient-specific booking behavior.
5. **Validation and test cleanup.** Consolidate tests around the shared session.
   Replace obsolete separate-creation cases and move shared behavior checks to
   their owning layer. Add coverage in `ScheduleEditorSessionTests` for switches in
   both directions, interval preservation after movement and date changes, field
   clearing, one visible draft, active-type saving, missing patient, blank label,
   failed save, and router session replacement. Extend focused model and routing
   tests where needed. Remove duplicate coverage only when the same behavior and
   failure paths remain covered. Check segments, keyboard focus, swipe dismissal, and hold
   behavior in Simulator. Use a UI test only for behavior unit tests cannot verify.
6. **Documentation and diagrams.** Reconcile maintained timeline, booking, routing,
   and architecture guidance with the final ownership model. Remove obsolete
   rules and duplicate explanations. Locate maintained architecture and flow
   diagrams, update their source and any rendered copies, and check their links.
   No diagram source was found in this checkout during planning; find its owning
   source if it is stored elsewhere. Do not create a second copy to work around a
   missing source. Keep implemented specs and historical plans unchanged.
7. **Final simplification review and checks.** Review the complete diff for the
   cleanup requirements below. Preserve applicable code comments and run the
   repository comment check, focused tests, a build, and `git diff --check`. Mark
   this spec implemented only after implementation, cleanup, and validation are
   complete. Report any cleanup or diagram source that remains blocked.

## Cleanup requirements

Cleanup is part of this feature's completion criteria. Review the affected flow
after integration; adding a common container alone does not complete the work.

- Give shared draft timing, gesture state, sheet visibility, save state, and errors
  one owner where their behavior is shared. Review `isSelectingPatient` and
  `isEditingLabel` rather than retaining parallel flags behind another flag.
- Remove redundant sheet wrappers, navigation containers, presentation modifiers,
  route requests, creation helpers, callbacks, and unused files once their callers
  use the shared flow. Update call sites instead of keeping compatibility wrappers
  for the removed internal flow.
- Review repeated switches in `ScheduleEditorSession` and duplicated date,
  adjustment, and scrolling code. Consolidate common behavior without adding a
  generic editor framework or merging distinct persistence rules just to reduce
  line count. Keep the different patient validation, appointment status and charge
  checks, and unavailable-time deletion behavior explicit.
- Review `ScheduleEditorSessionTests`, `AppointmentBookingModelTests`,
  `UnavailableTimeTests`, `MixedScheduleTests`, and `RouterTests` together. Replace
  assumptions about the separate block creation route, opening-time default,
  60-minute duration, and disabled swipe dismissal where they concern creation.
  Keep coverage for saved-item editing and domain-specific failures.
- Parameterize shared behavior tests where the scenarios have the same contract.
  Remove redundant fixtures and helpers after moving or deleting tests. Do not
  replace distinct regression cases with a broad test that misses their cause.
- Keep each consequential rule in one maintained guide and link to it. Diagrams
  must show the final presentation and draft ownership; remove obsolete separate
  creation branches. Avoid documenting a list of implementation changes.
- Before completion, search for retired symbols and old flow descriptions in
  active code, tests, maintained guides, and diagram sources. Resolve remaining
  references, review deleted comments, and summarize the cleanup actually done.

## Acceptance checks

- Both generic entry points can create either type through the same sheet.
- A segment change neither saves data nor creates a second visible draft.
- Switching preserves date, start, and duration after movement, resizing, or a
  date change. It clears the previous segment's entries, including on a round trip.
- Both generic entry points start on Appointment for 30 minutes. A new session does
  not remember the previous session's segment.
- A hold can move its draft before sheet presentation; the sheet does not interrupt
  the gesture.
- Patient creation cancel or failure preserves the surrounding creation session.
- Done saves only the active type. A failed save retains that draft for retry.
- Back and swipe dismissal keep the current draft. Reopening without a switch
  keeps its entries. Cancel confirms before discarding the session.
- A late completion cannot close or alter a newer router session.
- Saved-item edit sheets and patient-specific booking have no type selector.
- The old separate creation flow has no unused routes, sheet hosts, flags, or
  compatibility code. Shared behavior has one clear owner.
- Tests cover the new contract without retaining obsolete creation expectations
  or duplicate setup. Distinct domain and regression coverage remains intact.
- Maintained guides and any affected architecture diagrams agree with the final
  code. Each changed rule has one documentation home.
