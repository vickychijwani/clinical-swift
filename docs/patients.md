# Patients List Architecture

This document captures the deliberate constraints an agent is likely to break if it edits patient list grouping, search, or row metadata without context.

## Invariants

- A patient is valid only when at least one of name or phone number is present.
- Patients without a name display as `Unknown Patient`, but that fallback is presentation-only. Do not store it as a fake name.
- Patient name search is word-prefix based and order-independent. Do not use substring matching because short queries like `an` should find `Anjali Desai` and `Mary Ann`, but not `Rani Dutta`.
- Age is derived from date of birth at render/test time. Do not store age as independent patient state because it drifts every birthday.
- Next appointment metadata is list/read-model data, not intrinsic patient state. Keep it off `Patient` so appointment changes remain the only source of truth.
- Contact import only prefills a blank patient name and never overwrites an existing one. It removes the bookkeeping prefixes `Patient `, `Website Lead `, and `Lead ` from imported names. A `Patient Called ` contact must not prefill a name because that label represents an unknown caller rather than a patient identity.

## Do Not Reintroduce

## Edge Cases
