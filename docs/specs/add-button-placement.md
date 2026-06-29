----
status: shelved
----

# Add button placement at bottom trailing edge

## Summary

This work item considered moving the Schedule and Patients add actions from their top toolbars to
a persistent Liquid Glass button at the bottom trailing edge, visually separated from tab
navigation.

## Decision

Shelve the persistent tab-bar-adjacent button. Keep add actions scoped to the tab whose content they
affect. If improved thumb reach becomes a priority, move each action to that tab's system bottom
toolbar:

- Schedule: New Appointment.
- Patients: New Patient.

Do not model either action as a tab or place it inside the tab bar. A tab bar represents top-level
navigation; controls that act on the current view belong in a toolbar. Keeping the actions
feature-local also preserves their clear meaning and avoids turning a visually identical persistent
"+" button into a different command after every tab switch.

## Feasibility Findings

- On the current iOS 26 target, `tabViewBottomAccessory` can host persistent controls, but its
  system placement is above the normal tab bar and inline when the tab bar collapses. It does not
  provide the isolated trailing action placement used by the dedicated Search tab.
- A custom bottom-trailing overlay could reproduce the desired position, but the app would then own
  tab-bar clearance, minimization, keyboard, orientation, and size-class behavior. That complexity
  is not justified for these contextual actions.
- A prominent trailing tab is available in newer platform APIs, but it remains a navigation
  destination rather than an action. Do not intercept a tab selection to present an add sheet;
  doing so would give the control misleading tab semantics.
- A native source-to-sheet animation is feasible with `matchedTransitionSource` and
  `navigationTransition(.zoom(...))`. This makes the sheet expand from and collapse back into its
  source button, but it is a zoom presentation transition rather than a literal Liquid Glass shape
  morph. This animation can be evaluated independently if the actions move to bottom toolbars.

## Recommendation

Use a system `ToolbarItem` with `.bottomBar` placement inside each tab when thumb reach outweighs
the additional visual weight of a bottom toolbar above the tab bar. Let SwiftUI manage the toolbar's
safe areas, adaptation, and Liquid Glass appearance; do not recreate those behaviors with an app
overlay.

Before adopting bottom toolbars, prototype Schedule and Patients together on iPhone and verify that
the stacked toolbar and tab bar do not feel visually heavy. Until that comparison demonstrates a
clear improvement over the existing top-trailing actions, retain the current placement.

## Reconsider When

- The add actions become frequent enough that top placement is a demonstrated usability problem.
- A platform API provides an action-specific trailing tab-bar placement without representing the
  action as navigation.
- A small visual prototype confirms that per-tab bottom toolbars improve reach without crowding the
  content or tab bar.
