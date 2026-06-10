# Patients List Architecture

This document captures the deliberate constraints an agent is likely to break if it edits patient list grouping, search, or row metadata without context.

## Invariants

- A patient is valid only when at least one of name or phone number is present.
- Patients without a name display as `Unknown Patient`, but that fallback is presentation-only.
- Age is derived from date of birth at render/test time. Do not store age as independent patient state because it drifts every birthday.

## Do Not Reintroduce

## Edge Cases
