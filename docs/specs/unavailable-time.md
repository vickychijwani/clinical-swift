---
status: implemented
---

# Block off unavailable time ranges

## Purpose

Let the clinic owner mark unavailable time for travel, holidays, or other periods. Show these blocks on the schedule for visibility and planning. Appointments can overlap a block because other doctors may be available.

## Proposed first version

- Create, edit, and delete a block from the Schedule tab.
- Store one optional free-text label, start time and duration in minutes, just like appointment records.
- Ensure the block falls entirely within clinic hours (including break time - partial or complete overlap with break time is allowed).
- Render each block as a card with a muted surface and `nosign` SF symbol on the card. Show its label and start time, just like appointment cards. Use the same timeline scale and overlap layout as appointment cards so both remain visible and selectable.
- Blocks are for display and planning only. Keep appointment time suggestions, manual time selection, and saving unchanged.
- Allow a block to overlap existing appointments without a conflict confirmation. Keep those appointments unchanged.
- Confirm deletion and discard of unsaved changes.

## Recommendation and assumptions

Store blocks as separate records in Clinical. The current Calendar integration sends appointment changes to Calendar; it does not import Calendar changes. Use Clinical as the source of truth for this version.
Each block records the clinic owner's unavailable time. Recurring blocks, doctor assignments, and Calendar import are outside this first version.

Use a card layout similar to appointments. A muted surface and `nosign` icon identify the block while preserving the schedule's existing layout. Keep block labels and appointment details visible when their ranges overlap.

## Acceptance checks

Blocks remain after an app restart. Blocks use the same card layout as appointments. Blocks and overlapping appointments remain visible and selectable. Appointment suggestions, creation, and editing behave the same with or without a block. Editing or deleting a block updates the schedule without changing appointments.
