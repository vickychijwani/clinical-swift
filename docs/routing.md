# Routing Architecture

This document captures the app-level presentation rules that must remain consistent across tabs and external entry points.

## Invariants

- The router owns one app-level presentation at a time. Details, appointment booking/editing, appointment messaging, and patient creation/editing must not maintain competing presentation intent in separate state.
- Newly triggered app-level actions are latest-wins interruptions. Discard the current presentation and any unsaved transient state; never restore it after the new action ends.
- SwiftUI may require the current sheet to finish dismissing before its replacement appears. Retain only the newest requested replacement during that handoff rather than building a queue.
- Replacing one active details destination with another may reuse the stable sheet session for responsiveness, but it must replace the root and clear modal history. This intentionally supersedes the new-presentation-identity rule for external links in the implemented details-sheet specification; root replacement still preserves its user-facing requirement that the external destination starts with an xmark and no prior history.
- Details navigation history belongs to the details presentation. Every push, pop, and root replacement must pass through router-owned mutation so route-specific invariants cannot be bypassed by a writable navigation path.
- Appointment routes may open immediately from an ID. Until the appointment record resolves and the Schedule tab is showing the same calendar day, render neutral sheet content rather than contradictory appointment details.
- Keep each details destination's navigation title and toolbar attached to its stable route view, outside loading, alignment, and unavailable-content branches. Covered routes may remain mounted by `NavigationStack`; withdrawing their navigation preferences during a push can leave stale chrome when the user navigates back.
- External schedule and list destinations interrupt any app-level presentation before changing the underlying tab or selection.

## Do Not Reintroduce

- Suspended details sessions or restoration after booking, editing, or messaging. Old state competing with a newer user action makes routing order-dependent and confusing.
- Parallel optional request properties in the Router as independent sources of truth. They allow multiple sheet hosts to believe they should present simultaneously.
- Appointment-date synchronization in individual callers. Widget, URL, sheet-navigation, and future App Intent entry points must all receive the same enforcement at the shared route boundary.
