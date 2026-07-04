----
status: implemented
----

# Appointment Status Actions

## Summary

Allow a scheduled appointment to be marked completed or cancelled from its details sheet. Both
actions require confirmation. Completion keeps the appointment visible with reduced visual
emphasis; cancellation retains the database record but removes it from all normal product views and
derived counts.

## Status Model

- Persisted appointments start as `scheduled` and may end as `completed` or `cancelled`.
- The only state-changing transitions are:
  - `scheduled` -> `completed`
  - `scheduled` -> `cancelled`
- A status-only request from any persisted status to itself is valid and idempotent. If no other
  fields changed, treat it as success without rewriting the record or changing `updatedAt`.
- An update that keeps the same status but changes other permitted appointment fields is not an
  idempotent status-only request. Allow the field changes and update `updatedAt`; for example,
  rescheduling a scheduled appointment must remain valid.
- `completed` and `cancelled` are terminal. Neither may transition to another status.
- `draft` is transient booking UI state and is not part of the persisted state machine. It must not
  be accepted by persistence APIs or stored in the appointments table.
- Centralize transition validation in the appointment domain rather than scattering status checks
  across views.
- Apply status changes through one transactional persistence operation that validates the current
  stored status and updates `status` and `updatedAt` atomically. A stale UI or competing write must
  not overwrite a terminal status.
- A database constraint may restrict stored status values, but it does not replace transition
  validation because a row constraint cannot express the previous-to-next state change by itself.

## Details Sheet Actions

- Show status actions only when the currently loaded appointment is `scheduled`, whether appointment
  details is the sheet root or a pushed destination.
- Place a dedicated button row directly below the appointment details card, within the fitted sheet
  content. Keep Edit in the trailing toolbar because it opens a separate workflow; status actions
  belong beside the record whose lifecycle they change.
- Use explicit text labels, `Complete` and `Cancel Appointment`. Give completion the primary visual
  emphasis and cancellation a destructive role without making it the visually dominant action.
- Pair the labels with simple SF Symbols: `checkmark` for `Complete` and `xmark` for
  `Cancel Appointment`.
- Keep the action row visible in the fitted presentation. Grow the fitted sheet to include the main
  details card and both actions together rather than requiring the user to expand the sheet.
- Do not place these two actions in a toolbar menu. They are the primary actions for a scheduled
  appointment, and hiding them would make the lifecycle controls harder to discover.
- Hide the complete, cancel, and edit actions for completed or cancelled appointments.
- While a confirmed status write is in progress, prevent duplicate submissions. Dismiss the details
  sheet only after the write succeeds.
- If persistence fails, keep the sheet open and show an error prompt. Do not present a successful
  state or dismiss before persistence completes.
- If the appointment changed status after the details were loaded, do not overwrite the newer
  status. Refresh the details and explain that the appointment was already updated.

## Complete Appointment

- Selecting `Complete` presents a confirmation alert.
- The alert identifies the action as completing the appointment and provides `Complete` and `Not
  Yet` choices.
- `Not Yet` dismisses only the alert and makes no change.
- Confirming performs `scheduled` -> `completed`.
- After a successful write, dismiss the complete details flow, including any local navigation
  history, and reveal the schedule.
- Keep the completed appointment on the schedule. Animate its card into a persistent, subtly muted
  appearance so it remains legible and selectable but is visually subordinate to scheduled work.
- Completed appointments remain eligible for normal appointment totals and the future patient
  appointment history.

## Cancel Appointment

- Selecting `Cancel Appointment` presents a destructive confirmation alert.
- The alert explains that the appointment will be hidden from the schedule and appointment history,
  and provides `Cancel Appointment` and `Keep Scheduled` choices.
- `Keep Scheduled` dismisses only the alert and makes no change.
- Confirming performs `scheduled` -> `cancelled`.
- After a successful write, dismiss the complete details flow, including any local navigation
  history. Remove the appointment card from the schedule rather than rendering a cancelled style.
- Retain the cancelled row in SQLite for audit and possible future administrative use.
- Exclude cancelled appointments from every normal user-facing appointment query and derived value,
  including:
  - schedule timelines;
  - appointment detail routes;
  - patient appointment histories;
  - next-appointment metadata;
  - appointment totals and other rollups;
  - booking slot suggestions or any future availability inputs.
- Administrative or audit features may query cancelled rows explicitly in the future. Normal read
  APIs must exclude them by default so each new feature does not have to remember this policy.

## Read Semantics

- Schedule queries return `scheduled` and `completed` appointments, never `cancelled` appointments.
- Appointment detail queries return `scheduled` and `completed` appointments. A direct route to a
  cancelled appointment uses the existing unavailable state rather than exposing the retained row.
- “Next appointment” metadata considers only future `scheduled` appointments. A future-dated
  completed row must not be presented as upcoming work.
- General appointment histories and totals include `scheduled` and `completed`, but exclude
  `cancelled`, unless an explicitly administrative query requests cancellation records.

## Acceptance Criteria

- Scheduled appointment details show `Complete`, `Cancel Appointment`, and the existing Edit action.
- Completed and cancelled appointment details expose no edit or status-changing actions.
- Declining either confirmation leaves the appointment and sheet unchanged.
- Confirming completion persists `completed`, updates `updatedAt`, dismisses the details flow, and
  leaves a muted but usable card on the schedule.
- Confirming cancellation persists `cancelled`, updates `updatedAt`, dismisses the details flow, and
  removes the card from the schedule.
- A cancelled appointment remains in the appointments table but is absent from normal details,
  schedules, patient metadata, histories, counts, and scheduling inputs.
- A completed appointment remains visible on the schedule and participates in normal histories and
  totals, but not in “next appointment” metadata.
- Invalid terminal-state transitions are rejected by the domain and persistence boundary even when
  invoked outside the details UI.
- Repeating a status-only request for the current persisted status succeeds without changing
  `updatedAt`; an update that also changes permitted fields persists those changes and advances
  `updatedAt`.
- Competing status writes cannot turn one terminal state into the other.
- Persistence failure leaves the details flow visible and reports the failure without showing a
  false successful state.

## Recommended Tests

- Domain tests cover both allowed state changes, all self-transitions, terminal-state rejection, and
  rejection of `draft` at the persistence boundary.
- Persistence tests cover atomic status updates, `updatedAt`, status-only idempotent no-op behavior,
  same-status updates to other fields, stale-write rejection, and retention of cancelled rows.
- Query tests prove cancelled rows are excluded from the schedule, details, next appointment, and
  count/history query families, while completed rows follow the read semantics above.
- View or model tests cover action visibility in the fitted presentation, confirmation cancellation,
  successful dismissal, persistent completed styling, and write-failure behavior. Prefer unit
  coverage over UI tests unless the interaction cannot be tested below the UI layer.
