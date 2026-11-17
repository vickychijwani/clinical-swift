---
status: implemented
---

# Shared tray presentation

## Purpose

Generalize the custom tray and replace native sheets across the app. Keep the
tray independent of details routes, payment drafts, and feature-specific text.

## Requirements

- Give shared tray motion, geometry, and presentation lifecycle one owner.
- Keep feature state, save rules, discard decisions, and prompt text in the
  feature that owns them. The tray must not inspect payment or patient models.
- Preserve session checks that prevent late callbacks from changing a newer flow.
- Build on the details tray pilot. Preserve its motion and session safeguards
  while removing its feature dependencies.
- Complete the migration and remove obsolete presentation code. A name change
  or a second wrapper around the details tray does not meet this requirement.

## Agreed behavior

- Replace all app-owned native sheets with the shared tray. Keep Apple Contacts
  and SMS screens in their standard native presentation.
- Use one tray surface for child steps. Change its content and height in place.
  Back returns to the parent and preserves the parent draft.
- Outside tap and swipe-to-dismiss have the same result and the same enabled
  state. Preserve each flow's current restrictions, including restrictions for
  unsaved changes. Do not enable these actions merely because a confirmation
  prompt is available. Explicit Close and Cancel keep their existing rules.
- Confirm before an explicit dismissal loses guarded draft changes, and block
  dismissal during a save. Closing schedule field selection keeps the timeline
  draft active.
- Features own discard text and the state used to apply this policy.
- Preserve each screen's current sizing intent: fixed height, fitted content, or
  full height. Animate height changes between steps in the shared surface.
- Preserve current app-level replacement behavior for external actions. Do not
  add a discard prompt or change which request wins during replacement.
- Preserve logical dismissal boundaries within the shared surface. Dismissing
  date of birth returns to the patient form. Dismissing a details flow closes
  its full navigation history, including appointment-to-patient navigation.
- Keep manual drag-to-resize deferred. The current screen controls the tray's
  height. Header swipe dismissal remains available where the feature permits it.
- Keep native error alerts and confirmation dialogs.
- Preserve current focus, keyboard, scroll, and background interaction behavior
  where it applies to the migrated flow. Scrolling content must not accidentally
  dismiss the tray. A blocked outside tap must not activate the background.

## Dismissal constraints found in the current app

The message screen disables interactive dismissal. Patient editing disables it
when the draft has changes. Appointment completion disables it while its form is
shown or a save is in progress. The shared tray must accept these restrictions
from the owning feature. Outside tap must not bypass any of them.

## Scope

App-owned sheets include details and appointment completion, patient editing,
schedule field selection, appointment messages, backup settings, and date of
birth selection. Patient creation can open from schedule field selection.
Contacts and SMS use Apple view controllers through native sheet presenters and
remain native. Previews must use the shared tray when they show an app-owned
sheet. System authentication and permission prompts keep their standard behavior.

This change does not add manual height resizing, change draft commit boundaries,
or change the router's policy for external interruptions. Existing routing
constraints are defined in [routing](../routing.md).

## Acceptance criteria

- The shared tray has no dependency on `Router`, `DetailsPresentation`, payment
  state, or a feature-specific height name such as `completion`.
- Features provide their content, sizing needs, and dismissal policy through a
  small shared interface. Do not create a generic feature workflow framework.
- Retained exit content has no authority to save or change routes. An exit
  callback can finish only the session that started it.
- Closing schedule field selection keeps the timeline draft active.
- A failed save keeps the draft and error available for retry.
- Supported navigation and keyboard states keep fields and actions reachable.
- Parent state survives child navigation, including unsaved form values, search,
  and the timeline draft. Child cancellation does not discard its parent.
- Saving a new patient from booking keeps the current patient-selection result
  and return behavior. The shared surface does not add an extra Back step.
- Outside tap and swipe have matching eligibility and dismissal scope in each
  migrated flow, including dirty and saving states.
- Fixed, fitted, and full-height screens keep their intended bounds. Child
  transitions change the existing surface without a close-and-reopen flash.
- Apple Contacts and SMS can open above a tray and return to the same active
  flow. Their callbacks cannot change a replacement flow.
- All app-owned sheet call sites and previews use the shared tray. Remove
  obsolete native hosts, the details-only native comparison path, and unused
  sheet sizing or dismissal wrappers after their callers migrate. Preserve
  applicable comments about layout and session constraints beside their owners.
- Each remaining native sheet presenter serves an agreed Apple system screen.

## Validation

Use unit tests for layout resolution, shared presentation lifecycle, dismissal
eligibility, and stale callbacks. Retain feature tests for draft ownership,
save failures, and external interruptions. Verify child navigation, outside tap,
header swipe, keyboard visibility, scroll behavior, and system-screen return in
the simulator. Use UI tests only where unit tests cannot establish the behavior.

Check the complete migration for retired sheet code and feature dependencies in
the shared tray. Update maintained guides only where a documented decision
changes. Mark this spec implemented after migration and validation are complete.

## Status

Implemented and validated in the simulator. Manual height resizing remains deferred.
