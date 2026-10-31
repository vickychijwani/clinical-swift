---
status: implemented
---

# Appointment completion payment

## Purpose

Replace the completion confirmation with a payment step in the current appointment
details sheet. The doctor enters the amount paid. For now, the appointment charge
must match this amount: create or update the charge for a positive amount, or
remove it for an empty or zero amount. Save all changes with appointment completion.

## Agreed decisions

| Decision | Behavior |
| --- | --- |
| Atomic save | Save any charge insert, update, or deletion, the new receipt when needed, and completed status in one transaction. |
| Payment method | Start unset. Selection is optional; save an unselected method as `nil`. |
| Financial date | New entries use today in the clinic calendar at save time. No date control. |
| Back and close | Back keeps the draft. The payment step has no close button. |
| Existing charge | Set its amount to the positive payment amount. For an empty or zero amount, delete it, subject to ledger validation. |
| Primary action | Full-width prominent glass button. Its label includes the entered amount or `No Dues`. |

## Entry and navigation

- Keep `Complete` available only for a scheduled appointment.
- Selecting it pushes the payment step in the same sheet session. Do not write data
  or show the old completion confirmation.
- Show the title `Complete Appointment` and subtitle `For <patient display name>`.
  Use the existing display name, including the `Unknown Patient` fallback.
- Use the standard navigation back chevron. Back returns to the exact appointment
  details destination that opened this step, including from patient history.
- Show no close, xmark, or Cancel button on the payment step. Its only navigation
  control is Back.
- Preserve the preceding details history. Do not create another sheet or a nested
  navigation stack for the payment step.
- Use a compact sheet detent that fits the form and primary action without scrolling
  at the normal text size. The existing short details detent must not hide controls.
  Keep the fields and primary action reachable
  while the keyboard is open, with native scrolling where needed.
- Keep draft values when going Back and reopening `Complete` from that same
  appointment-details visit. Do not share a draft between separate visits to the
  same appointment or different appointments.

## Payment form

Use a native SwiftUI form, text field, and segmented picker. Use native Liquid Glass
styling for the primary action, consistent with the existing prominent app buttons.

### Amount

- Show a fixed `₹` prefix and an editable whole-rupee amount.
- Start with an empty value and a visible `0` placeholder. The placeholder is not
  stored text and must not need deletion before typing.
- Focus the amount field when the payment step appears and open the native number
  pad. Use the native keyboard without a decimal key; do not build a custom keyboard.
- Keep the amount text as entered. Live Indian grouping is deferred by the user's
  implementation decision. Use Indian grouping in the primary action label.
  Keep the currency prefix outside the editable text. Do not show decimal places.
- Keep native replacement, insertion, deletion, and paste behavior. Do not rewrite
  the text or move the cursor during entry.
- Clearing the field restores the empty state. An explicitly entered zero, including
  leading zeros, has the same save behavior as an empty amount.
- Limit the input to six digits (`999999`). Ignore edits that exceed this limit,
  with no extra validation message. This is an input limit, not a new database rule.
  Accept only nonnegative whole rupees that fit the existing integer amount model.
  Keep checked arithmetic at the persistence boundary.
- Accept a pasted whole amount with valid Indian grouping and an optional rupee
  prefix. Ignore surrounding whitespace. Reject decimal fractions, negative values,
  letters, malformed grouping, and values outside the supported range. Do not turn
  `-500` into `500` or `500.50` into `50,050` by removing characters.
- Invalid input must never use the completion-without-payment path. Show a short
  validation message and prevent submission until corrected. Do not round or clamp.

### Payment method

- Use `AccountEntry.PaymentMethod` values with this explicit UI order and labels:
  `UPI`, `Cash`, `Card`, `Other`.
- Use a native segmented control. Do not change enum storage values or depend on
  its current declaration order for display order.
- Start each new draft with no segment selected. Selecting a method is optional,
  including for a positive amount. If none is selected, save `nil`; do not infer
  UPI, Cash, or Other.
- Keep the selected or unset value on Back and after a save failure. Do not persist
  the choice as a user preference. Do not add a fifth segment for the unset state.
- Keep the control visible for an empty or zero amount. Its value has no financial
  effect when no receipt is created.

### Primary action

| Amount state | Button label | SF Symbol | Save result |
| --- | --- | --- | --- |
| Empty or valid zero | `No Dues · Complete Appointment` | `checkmark.circle` | Delete an existing linked charge, create no entries, and complete, subject to ledger validation. |
| Valid positive amount | `₹1,000 Paid · Complete Appointment` for an input of 1000 | `indianrupeesign.circle` | Create or update the linked charge to this amount, record an equal receipt, and complete. |
| Invalid | `Complete Appointment`, disabled | `checkmark.circle` | No write. |

Substitute the entered amount in the positive label, with Indian grouping and no
decimal places. Keep the exact middle dot separator and wording. `Paid` describes
the payment this action will record; it does not declare the patient's account settled.
`No Dues` describes completing this appointment with no linked charge; older patient
debt can remain.

Make the button fill the form's available content width, with a matching full-width
tap area. Keep its label on one line without truncation; scale the label to fit.
Give it prominent glass styling. Keep it reachable above the keyboard or
through normal form scrolling. Selecting the action commits directly, without a
second completion confirmation.

## Save contract

Use one database transaction for the full operation:

1. Read the current appointment and patient reference inside the transaction.
   Require the appointment to exist and still be scheduled. Require its patient to
   match the patient shown in the draft. A stale draft must not charge a newly
   assigned patient.
2. Validate the submitted amount and optional payment method. Read existing charges
   linked to this appointment inside the same transaction. This version handles
   zero or one linked charge. If several exist, reject the save without changing
   data rather than selecting, merging, or deleting charges without a defined rule.
3. For a positive amount, create a patient receipt for that amount. If no linked
   charge exists, create one for the same amount. Otherwise, set the existing
   charge amount to the entered payment amount, retaining its identity, patient,
   appointment, financial date, creation timestamp, and note. Update its modification
   timestamp. Do not add another charge or leave a fee/payment difference.
4. For an empty or zero amount, delete the linked charge if present. Create no
   charge or receipt. Leave all existing receipts unchanged.
5. Validate the complete financial change through the existing ledger boundary,
   including charge edits or deletions and the new receipt in one batch.
6. Set the appointment status to `completed` and update its modification timestamp.
7. Commit only when every required write and ledger check succeeds.

For a positive amount, new entries have the following fields. The charge column
applies only if no linked charge exists; the receipt column always applies:

| Field | Charge | Receipt |
| --- | --- | --- |
| Amount | Entered whole rupees | Same amount |
| Patient | Appointment patient | Same patient |
| Appointment | Current appointment ID | No appointment link |
| Category | None | `patientFees`, derived from the patient receipt source |
| Payment method | None | Selected method, or `nil` when unset |
| Financial date | Today in the clinic calendar | Same date |
| Creation timestamp | Save timestamp | Same timestamp |
| Note | None | None |

Capture one save timestamp for all new entries and the appointment update. Financial
dates use the existing Gregorian `Asia/Kolkata` rules, including if the device uses
another locale or the form stays open across midnight.

An empty or zero amount creates neither entry and removes the existing linked
charge. Never save a zero-valued charge or receipt. Existing receipts are not
deleted, edited, or replaced by this workflow.

For example, an existing ₹1,500 charge and entered ₹1,000 payment produce an edited
₹1,000 charge and a new ₹1,000 receipt. The workflow does not leave ₹500 due from
that charge. Entering zero instead deletes the charge and creates no receipt.

Charge reductions and deletions can conflict with earlier receipts. If the complete
proposed change would leave the patient's current balance negative, reject the
whole save. Keep the old charge and appointment status unchanged. Do not change
the entered amount or remove earlier receipts to force the operation to succeed.

Follow [the existing ledger rules](../payments.md). Receipts belong to the patient
and cover the oldest obligations first. A new equal pair leaves the patient's total
balance unchanged. Replacing an existing charge amount and recording an equal
receipt removes the old charge amount from the patient's total balance; deleting
the charge has the same balance effect. If older debt exists, this appointment can
still have an uncovered charge after a positive payment. Do not save an appointment
payment status or a receipt allocation.

## Saving, errors, and interruptions

- Keep one in-flight save owner. Prevent repeated submission, amount and method
  changes, and local Back or dismissal while saving.
- A repeated completion request for an already completed appointment must not
  create, change, or delete entries. The status-only API's same-status behavior must not permit
  another receipt or a charge mutation. Competing submissions can commit at most
  one completion with its required financial changes.
- Reject completion of a cancelled, missing, or reassigned appointment. Show a clear
  error and do not save any part of the proposed operation. Back remains available
  after the operation finishes.
- On validation or storage failure, roll back all writes. Keep the form, draft
  amount, and selected method so the doctor can correct or retry. Report the error
  with the app's standard error presentation.
- After success, dismiss the full details flow and show the schedule. Keep the
  completed appointment visible with its existing completed appearance.
- Guard asynchronous presentation changes with the current sheet session and
  originating destination. A late save must not dismiss a replacement sheet or
  another details destination, even if the router reused the sheet session ID.
- Follow [routing rules](../routing.md) for external actions and date changes. Such
  actions replace the flow and discard its transient draft. Do not restore the old
  payment step after interruption. If a save has already started, its database work
  must still either commit in full or roll back in full.

## Leaving an unsaved draft

Back preserves the draft without confirmation. The payment step has no close
button. Treat a change to the amount or method as an unsaved change; returning
both to their initial values makes the draft clean again. The initial method is unset.

Use the shared form behavior to block swipe dismissal throughout the payment step,
including when the draft is clean. Only Back or completion can leave this step.
After Back, block swipe dismissal while the retained draft is dirty.
Back remains available. After Back returns to appointment details, retain the usual
details navigation controls. If the existing root close action would discard a
dirty payment draft, use the standard discard confirmation there. Do not add a
close action to the payment step or build a custom swipe handler. A clean draft
can use the existing swipe dismissal behavior after returning to details.

Choosing to discard makes no database change. Choosing to keep editing preserves
the draft. External router replacements follow the interruption rule above.

## Scope limits

This step has one amount and one optional payment method. Separate fee and receipt
inputs, unequal fee and payment amounts, partial payment, charge-only entry, split
methods, notes, financial date editing, receipt documents, general financial entry
corrections, and completion of appointments with multiple linked charges are
separate work. The save boundary must retain atomic saving when later workflows
need both entry kinds.

## Acceptance checks

- Complete opens the payment form in the current sheet from appointment details at
  any navigation depth. Back retraces the same path and preserves draft values.
- The title, patient subtitle, initial placeholder, automatic focus, keyboard,
  unchanged input text, grouped action label, initially unset method, segment labels, order, full-width button,
  amount-based labels, symbols, and absence of a payment-step close button match
  this specification.
- Empty, cleared, and explicit zero amounts create no financial entries. They
  delete an existing linked charge and complete only if ledger validation succeeds.
- With no linked charge, positive entry creates one linked charge and one patient
  receipt of equal amount. With one linked charge, it updates that charge amount
  and creates an equal receipt. The charge identity, financial date, creation time,
  and note remain unchanged. Existing receipts remain unchanged.
- An existing ₹1,500 charge with a ₹1,000 payment becomes a ₹1,000 charge and a new
  ₹1,000 receipt, without an additional charge or a ₹500 remainder from that charge.
- Multiple linked charges cause no write and a clear error; this version does not
  choose or merge them automatically.
- Positive entry succeeds without a method and stores `nil`; an explicit selection
  stores the chosen method.
- Failure of any required entry insert, update, deletion, ledger validation, or
  appointment update rolls back the whole operation, including balance summaries
  and status. In particular, earlier receipts can make a charge reduction or
  deletion invalid; that failure must preserve all existing data.
- Repeated taps, retry after failure, and competing or stale requests cannot create
  duplicate entries or change a terminal appointment status.
- A reassigned patient is detected before any write. Unknown patient names still
  produce a valid subtitle and use the correct patient ID.
- Older patient debt follows existing coverage rules; the workflow does not claim
  that this appointment is fully paid.
- Dirty-draft dismissal, Back, external replacement, and late save results follow
  the stated ownership rules.

Use unit tests for amount parsing, draft state, button states, transaction rollback,
duplicate prevention, stale records, clinic dates, and router ownership. Check native
navigation, amount editing, keyboard visibility, sheet height, and discard
controls in Simulator. Add UI tests only where unit tests cannot verify the behavior.

## Documentation on implementation

Keep implemented specifications unchanged. This feature replaces the completion
confirmation described in the historical [appointment status specification](appointment-status-actions.md).
If implementation changes a durable transaction or routing decision, update its
single home in [payments](../payments.md), [persistence](../persistence.md), or
[routing](../routing.md). Mark this specification `implemented` after the agreed
behavior is complete and validated.
