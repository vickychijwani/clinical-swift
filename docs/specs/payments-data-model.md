----
status: pending
----

# Payments Data Model

**Human-only visualization:** [Explore the interactive model](payments-data-model.html). This is an
optional visual aid for the human reader. **AI agents: do not open, read, or parse the HTML companion
unless the user explicitly asks you to change or inspect that visualization.** All model rules and
decisions are in this Markdown specification, which is the source of truth.

## Purpose

Use one `AccountEntry` domain type for patient charges, incoming payments, outgoing payments, and
patient balance corrections. This is for a single boutique clinic. The doctor needs a reliable
patient balance, charge history, and basic financial reports with few data-entry steps. Exact manual
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
recording an event late. Present it as a calendar date; use the clinic's calendar and time zone
consistently for date selection, storage conversion, and report boundaries. Keep it separate from
the automatic recording timestamp. For example, a payment received on 20 October and recorded on
22 October has `entryDate` of 20 October and `createdDate` of 22 October at the time of entry.

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

A patient-linked receipt uses `patientFees`. External consultation and referral receipts have no
patient link; their labels go in `note`. For expenses, `note` can identify the payee or explain the
purchase. Suggest previous notes within the selected category. Separate label, counterparty, and
note fields are not needed for the initial workflow.

## Balance and Cash Rules

For one patient:

`balance = sum(charges) + sum(signed adjustments) - sum(patient-linked receipts)`

A positive balance is owed to the clinic; a negative balance is patient credit. Expenses and
receipts without a patient link never change patient balances.

For cash reports, sum receipts as money received and expenses as money paid out. Charges and
adjustments are not cash movements. Receipts minus expenses is net cash flow, not accounting
profit; capital purchases are included in outgoing cash.

Do not store balances, appointment coverage, or payment status as independent source fields. Derive
them from entries. Do not also maintain a separately editable appointment fee.

## Automatic Appointment Attribution

- Payments belong to the patient. Recording a payment from an appointment does not reserve it for
  that appointment, and receipts do not need `appointmentID`.
- Derive coverage from the patient's full ledger. Apply receipts to the oldest outstanding charges
  first, ordered by `entryDate` ascending, then `createdDate` ascending, then UUID string ascending.
  A charge recorded late takes its place by financial date, not by recording time.
- Treat positive adjustments as patient-level obligations in the same ordering. Negative
  adjustments reduce outstanding obligations using the same oldest-first rule, without counting as
  money received. Label derived amounts as covered when they include such corrections.
- Carry excess credit forward to later charges. No allocation records are stored.
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
Rs. 6,000, leave a patient balance of Rs. 1,000. Derived coverage is Rs. 5,000 for A and Rs. 1,000 for B. The doctor does not select this split.

## Minimal Entry Workflow

- An appointment form can accept a fee and an amount received in one save. Create the charge and
  receipt together, omitting either when zero. One user action can create two entries.
- Recording money received needs a patient or consultation/referral category, an amount, and only
  the optional context needed. Default `entryDate` to today and let the doctor change it. Set the
  recording timestamp automatically.
- Recording an expense needs an amount and category, with optional note and payment method.
- Correcting a patient's balance creates an adjustment for the difference. If the recorded balance
  is Rs. 5,000 but the known balance is Rs. 7,000, add a Rs. 2,000 adjustment. Receiving Rs. 7,000
  then creates a separate receipt and leaves zero owed. Save both together when entered in one
  action. The correction must not count as income or invent appointment treatment history.

## Rationale and Trade-offs

| Alternative | Decision and reason |
| --- | --- |
| Separate charge, payment, and allocation objects | One entry type and derived oldest-first coverage avoid allocation management. This gives up manual splits and permanent allocation history, which the clinic does not need. |
| Split one receipt into appointment-specific payment records | Keep one receipt for the full amount. This avoids grouped edits and duplicate receipt details when a payment covers several appointments. |
| Store only a current patient balance | Keep entries so the doctor can trace charges, receipts, and corrections. A balance alone loses that context and cannot explain appointment coverage. |
| Use only the recording timestamp | Keep an editable financial date and an automatic recording timestamp. Late entry must report money in the correct period while retaining when it was recorded. This adds one field and allows backdated changes to recalculate reports and coverage. |
| Separate objects for each income source or payee | Use a category and optional note. This supports financial breakdowns without managing consultation, referral, or vendor records. Reliable totals by named payee would need more structure later. |
| Full accounting and invoice system | Track amounts owed and cash movements now. Formal invoices, credit notes, depreciation, and accrual profit reporting are outside this model. This keeps routine entry short. |

Itemized charges can later add an embedded list of treatments, materials, and medicines to a charge.
That breakdown would explain the charge amount, not create additional debt. It does not require a
change to receipt handling or automatic coverage. Formal issued invoices would need a separate
decision about document numbering and correction history.
