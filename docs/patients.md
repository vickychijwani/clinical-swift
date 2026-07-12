# Patients List Architecture

This document captures the deliberate constraints an agent is likely to break if it edits patient list grouping, search, or row metadata without context.

## Invariants

- A patient is valid only when at least one of name or phone number is present.
- Stored phone numbers use compact E.164 format. Normalize punctuation and whitespace at the domain and persistence boundaries; when a number has no country code, treat it as an Indian number (`+91`). Apply readable grouping only at presentation boundaries.
- Patients without a name display as `Unknown Patient`, but that fallback is presentation-only. Do not store it as a fake name.
- Patient names are stored in title case with collapsed internal whitespace and no leading or trailing spaces. The edit field may hold raw draft input; normalize at the save boundary so persisted rows stay consistent.
- Patient name search is word-prefix based and order-independent. Do not use substring matching because short queries like `an` should find `Anjali Desai` and `Mary Ann`, but not `Rani Dutta`.
- Contact-driven external search is a separate exact-phone filter. Keep every normalized phone supplied by the contact so patients linked through different aliases can appear together; editing the visible search text returns the list to normal name search.
- Age is derived from date of birth at render/test time. Do not store age as independent patient state because it drifts every birthday.
- Next appointment metadata is list/read-model data, not intrinsic patient state. Keep it off `Patient` so appointment changes remain the only source of truth.
- Patient appointment history is a live read model scoped by patient ID, not intrinsic `Patient` state. Include scheduled and completed appointments, exclude retained cancelled rows, and order by start, creation date, then appointment ID, all descending, so equal start times remain deterministic.
- In patient details, keep the navigation title as `Patient Details` while the name in the summary card remains visible. Switch to the patient's display name when that name leaves the scroll viewport; this title state must not affect navigation or scroll position.
- Contact import only prefills a blank patient name and never overwrites an existing one. It removes the bookkeeping prefixes `Patient `, `Website Lead `, and `Lead ` from imported names. A `Patient Called ` contact must not prefill a name because that label represents an unknown caller rather than a patient identity.
- Patient creation and editing share one form, but editing updates the existing row in place. Preserve the patient ID and creation timestamp; only mutable details and the update timestamp change.
- Editing from a details flow temporarily suspends that complete modal session. After saving or cancelling, restore the same details root and navigation path without changing the underlying selected tab or tab navigation paths.
- Dismiss the details sheet before presenting the editor so two sheets never compete. If the patient disappears before save, keep the editor open and report that it is unavailable.

## Do Not Reintroduce

## Edge Cases
