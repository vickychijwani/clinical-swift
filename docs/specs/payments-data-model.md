----
status: pending
----

# Payments Data Model

**Human-only visualization:** [Explore the interactive model](payments-data-model.html). This is an
optional visual aid for the human reader. **AI agents: do not open, read, or parse the HTML companion
unless the user explicitly asks you to change or inspect that visualization.** All model rules and
decisions are in this Markdown specification, which is the source of truth.

## Purpose

Use one `AccountEntry` domain type for patient charges, incoming payments, outgoing payments,
opening balances, and corrections to incomplete financial history. This is for a single boutique
clinic. The doctor needs a reliable patient balance, charge history, and basic financial reports
with few data-entry steps. Exact manual
allocation of receipts to appointments is not required.

## Domain Model

Use the app's camelCase property names, `ID` suffixes, and Foundation `Date` type. Keep the domain
type separate from its database record, as described in `docs/persistence.md`.

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | `UUID` | Unique entry identifier. |
| `kind` | `AccountEntry.Kind` | `charge`, `receipt`, `expense`, `adjustment`. |
| `amount` | `Int` | Whole rupees. Charges, receipts, and expenses are positive. Adjustments can be positive or negative. |
| `entryDate` | `Date` | Editable date when the charge, payment, expense, or correction took effect. |
| `createdDate` | `Date` | Timestamp when the entry was recorded. |
| `patientID` | `UUID?` | Required for charges and adjustments; optional for receipts; absent for expenses. |
| `appointmentID` | `UUID?` | Optional charge-to-appointment link. |
| `category` | `AccountEntry.Category?` | Classification for receipts and expenses. |
| `note` | `String?` | Optional context, including a consultation label, referral label, or payee. |
| `paymentMethod` | `AccountEntry.PaymentMethod?` | `cash`, `upi`, `card`, `other`. Used for receipts and expenses. |

An amount of `5000` means Rs. 5,000. Do not store paise or use floating-point amounts. Skip entries
with a zero amount. Normalize blank notes to `nil`.

`createdDate` follows the existing `Patient` domain convention. Map it to `createdAt` in the database
record, which also has the standard `updatedAt` field. Creation time remains unchanged on edits.

`entryDate` is the financial event date. Default it to today and allow the doctor to change it when
recording an event late. Reject future financial dates for all entry kinds. Use the Gregorian
calendar and `Asia/Kolkata` time zone for date selection, storage conversion, and report boundaries,
even when the device uses another calendar or time zone. Normalize the value to the start of that
clinic calendar day. Keep it separate from the automatic recording timestamp. For example, a
payment received on 20 October and recorded on 22 October has `entryDate` of 20 October and
`createdDate` of 22 October at the time of entry.

Financial history and period reports use `entryDate`. A historical balance includes entries through
the selected financial date. Recording or changing a backdated entry can therefore change earlier
period totals. `createdDate` records when that information was entered; it does not replace the
financial date or provide a complete edit history.

## Categories

Require a category for receipts and expenses. Charges and adjustments do not need one. Categories
are enum values with fixed reporting-group mappings; groups are derived, not stored on each entry.

| Reporting group | Category values |
| --- | --- |
| Incoming | `patientFees`, `externalConsultations`, `referralCommissions`, `otherReceipts` |
| Operating | `rent`, `staff`, `consultants`, `utilities`, `materials`, `repairsAndMaintenance`, `otherOperatingCosts` |
| Capital | `equipmentPurchases`, `clinicImprovements` |

These are starting categories. Further categories can be added when needed. Repairs and equipment
purchases have separate categories because they belong to different reporting groups.

A receipt uses `patientFees` if and only if it has a patient link. All other receipt categories have
no patient link; consultation and referral labels go in `note`. For expenses, `note` can identify
the payee or explain the purchase. Suggest previous notes within the selected category. Separate
label, counterparty, and note fields are not needed for the initial workflow.

### Valid field combinations

| Kind | Amount | Patient | Appointment | Category | Payment method |
| --- | --- | --- | --- | --- | --- |
| Charge | Positive | Required | Optional; same patient | Absent | Absent |
| Receipt: patient fees | Positive | Required | Absent | `patientFees` | Optional |
| Receipt: other incoming | Positive | Absent | Absent | Another incoming category | Optional |
| Expense | Positive | Absent | Absent | Operating or capital category | Optional |
| Adjustment | Nonzero, signed | Required | Absent | Absent | Absent |

`note` is optional for all kinds. An omitted payment method remains unknown; do not infer cash.

## Balance and Cash Rules

For one patient:

`balance = sum(charges) + sum(signed adjustments) - sum(patient-linked receipts)`

A positive balance is owed to the clinic; zero means nothing is owed. Successful local saves must
leave each affected patient's current balance at zero or above. Expenses and receipts without a
patient link never change patient balances.

Validate the current balances after the complete proposed save, including edits and deletions.
Intermediate balances within the transaction can be negative; reject the complete save only if an
affected patient's final current balance is negative. Never change an entered amount to make it
pass. Refunds and unapplied current credit are outside this version.

Do not reject a save because an earlier historical balance becomes negative. Historical reports
show the signed balance from entries through the selected date without changing a negative result
to zero. For example, a Rs. 5,000 receipt dated 19 October and a Rs. 5,000 charge dated 20 October
are valid together: the current balance is zero, and the balance on 19 October is minus Rs. 5,000.

For cash reports, sum receipts as money received and expenses as money paid out. Charges and
adjustments are not cash movements. Receipts minus expenses is net cash flow, not accounting
profit; capital purchases are included in outgoing cash.

Do not store balances, appointment coverage, or payment status as independent source fields. Derive
them from entries. Do not also maintain a separately editable appointment fee.

Use edits to correct known charges or receipts. Keep adjustments for opening balances and
corrections to incomplete history where the missing or incorrect charge cannot be identified.
These adjustments change debt without representing a new treatment fee or cash movement. Do not
change an unrelated charge to make the patient's total match a known balance.

Maintain a derived `patientBalances` table with database triggers for fast current-balance reads,
positive-balance filters, and outstanding-balance totals. Entry inserts, updates, and deletions
update the summary in the same transaction. The ledger remains authoritative; the summary cannot
be edited through the app and can be rebuilt from entries. Read the final summaries for local
save validation. Historical balances and appointment coverage still derive from the ledger.

Exclude summaries from future cross-device sync. Each device builds them as ledger entries arrive;
an existing ledger can rebuild them with a grouped sum. During initial sync, balances represent
only received data until the initial import is complete. Future sync must define how to handle
partial imports and concurrent payments that produce credit; summary triggers alone do not enforce
a cross-device no-credit rule.

## Automatic Appointment Attribution

- Payments belong to the patient. Recording a payment from an appointment does not reserve it for
  that appointment, and receipts do not need `appointmentID`.
- Derive coverage from the patient's full ledger. Apply receipts to the oldest outstanding charges
  first, ordered by `entryDate` ascending, then `createdDate` ascending, then UUID string ascending.
  A charge recorded late takes its place by financial date, not by recording time.
- Treat positive adjustments as patient-level obligations in the same ordering. Negative
  adjustments reduce outstanding obligations using the same oldest-first rule, without counting as
  money received. Label derived amounts as covered when they include such corrections.
- Reject a complete local save that leaves a negative current patient balance. For historical
  coverage, carry any excess receipt or negative-adjustment amount as unallocated credit through
  the selected date. Never show a charge as covered beyond its amount. No allocation records are
  stored.
- Show appointment charges, derived coverage, and the remainder. Explain that payments are applied
  to oldest charges first. Patient-level adjustments remain visible in patient history.
- Editing an amount or financial date, or removing an entry, recalculates coverage. Historical
  appointment coverage is therefore a current calculation, not a permanent receipt-to-appointment
  assignment.
- If a charge has an appointment link, its patient must match that appointment's patient. Both
  references are deliberate: patient-level receipts and balances need `patientID`, while charge
  tracing needs `appointmentID`. This accepts the future sharing constraints of records with
  multiple foreign keys noted in `docs/persistence.md`.

Example: charges of Rs. 5,000 for appointment A and Rs. 2,000 for B, followed by receipts totaling
Rs. 6,000, leave a patient balance of Rs. 1,000. Derived coverage is Rs. 5,000 for A and Rs. 1,000
for B. The doctor does not select this split.

## Entry and Appointment Changes

- Several charges can link to one appointment. Derive its total from all linked charges.
- Charges can link to scheduled, completed, or cancelled appointments. Appointment status does
  not determine whether a financial obligation exists. A charge for an upcoming appointment can
  take effect today, but it cannot have a future financial date.
- Cancellation keeps linked charges. Any financial correction is an explicit separate action.
- Block appointment patient reassignment and physical deletion while linked charges exist.
  Moving or removing an appointment must not silently move debt or discard its context.
- Block patient deletion while any financial entries reference that patient, including when the
  balance is zero. Settled history is still financial history.
- Allow direct entry edits and deletion, subject to all field, reference, date, and balance rules.
  Preserve entry identity and creation time on edits. A full edit history is outside this version.
- Skip zero-valued new entries in combined workflows. An edit to zero is invalid; explicitly
  delete the existing entry when removal is intended.

## Minimal Entry Workflow

This work item implements the data layer. The workflows below define the transactions that later
screens must support; payment screens are separate work.

- An appointment form can accept a fee and an amount received in one save. Create the charge and
  receipt together, omitting either when zero. One user action can create two entries.
- Recording money received needs a patient or consultation/referral category, an amount, and only
  the optional context needed. Default `entryDate` to today and let the doctor change it. Set the
  recording timestamp automatically.
- Recording an expense needs an amount and category, with optional note and payment method.
- Correct a known charge or receipt by editing that entry, subject to current-balance validation.
- For an opening balance or incomplete history, create an adjustment for the difference. If the
  recorded balance is Rs. 5,000 but old records establish Rs. 7,000 owed without a full charge
  breakdown, add a Rs. 2,000 adjustment. Receiving Rs. 7,000 then creates a separate receipt and
  leaves zero owed. Save both together when entered in one action. The correction must not count
  as income or invent appointment treatment history.

## Rationale and Trade-offs

| Alternative | Decision and reason |
| --- | --- |
| Separate charge, payment, and allocation objects | One entry type and derived oldest-first coverage avoid allocation management. This gives up manual splits and permanent allocation history, which the clinic does not need. |
| Split one receipt into appointment-specific payment records | Keep one receipt for the full amount. This avoids grouped edits and duplicate receipt details when a payment covers several appointments. |
| Store only a current patient balance | Keep entries so the doctor can trace charges, receipts, and corrections. A balance alone loses that context and cannot explain appointment coverage. |
| Replace adjustments with charge edits | Edit known mistakes directly. Keep adjustments for opening balances and incomplete history so debt corrections do not change unrelated charges or appear as new treatment fees. |
| Use only the recording timestamp | Keep an editable financial date and an automatic recording timestamp. Late entry must report money in the correct period while retaining when it was recorded. This adds one field and allows backdated changes to recalculate reports and coverage. |
| Separate objects for each income source or payee | Use a category and optional note. This supports financial breakdowns without managing consultation, referral, or vendor records. Reliable totals by named payee would need more structure later. |
| Full accounting and invoice system | Track amounts owed and cash movements now. Formal invoices, credit notes, depreciation, and accrual profit reporting are outside this model. This keeps routine entry short. |

Itemized charges can later add an embedded list of treatments, materials, and medicines to a charge.
That breakdown would explain the charge amount, not create additional debt. It does not require a
change to receipt handling or automatic coverage. Formal issued invoices would need a separate
decision about document numbering and correction history.
