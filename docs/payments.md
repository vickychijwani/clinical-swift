# Payments

One account-entry table keeps the shared entry lifecycle, patient history, cash
reports, and combined saves together. Nullable storage fields stay at the record
boundary; reads must reject invalid combinations. Automatic coverage is a separate
decision: it avoids manual receipt allocation work for the clinic.

## Entry types and coverage

- A **charge** records treatment fees and increases patient debt. It can link to
  an appointment.
- A **receipt** records incoming money. A patient receipt reduces that patient's
  debt; other receipts record clinic income without changing patient debt.
- An **expense** records outgoing money, such as rent or equipment costs. It does
  not change patient debt.
- An **adjustment** increases or decreases patient debt without recording treatment
  fees or money received or paid. Use it for opening balances or incomplete history.

**Coverage** is the part of a charge or positive adjustment met by patient receipts
and negative adjustments. The app calculates it from the full patient ledger,
oldest obligation first. For charges of Rs. 3,000 and Rs. 2,000, a Rs. 4,000 receipt
covers the first charge fully and Rs. 1,000 of the second.

**Allocation** assigns a particular receipt to a particular charge. The app does
not store these links or ask the doctor to manage them. It combines receipts and
negative adjustments to calculate coverage. Any excess remains unallocated credit.

## Financial rules

- Amounts are whole rupees. Financial arithmetic must fail on integer overflow.
  Adjustments change debt without creating treatment fees or cash movements.
  An unknown payment method does not mean cash. Net cash flow includes capital
  expenses and is not profit.
- A complete local save must leave each affected patient's current balance
  nonnegative, including both patients when an entry moves. Intermediate credit
  is allowed so related corrections can succeed together. Use the batch write
  boundary; a caught failure must not leave part of the batch saved. Combined
  appointment and payment actions must propagate failure to their outer transaction.
- Historical balances remain signed. A receipt before its charge can create
  historical credit even when the final current balance is nonnegative. Backdated
  edits change past reports; creation timestamps are not an edit audit trail.
- Financial days use the Gregorian calendar in Asia/Kolkata, independent of device
  settings. Periods include the start day and exclude the end day. A balance through
  a selected date includes that whole day. Writes reject future clinic days.
- Known-balance corrections read stored history through the selected date inside
  the transaction, before adding a paired receipt. Screen state can be stale.
- Patient receipts belong to patients rather than appointments. Order coverage
  obligations by financial date, creation time, then UUID string. No appointment
  payment-status record is stored.
- Cancellation keeps linked charges. Financial history prevents patient deletion
  even when settled. Linked charges block appointment deletion and patient changes.

## Derived balances

Current summaries are rebuildable, device-local data maintained by entry triggers.
They allow signed totals for temporary credit and partial imports. Missing means
zero. Rebuild for repair or imports that bypass triggers, not on each read or launch.
SQLite snapshots retain these summaries; normal restore does not rebuild them.

Future sync must exclude summaries and apply entries with triggers installed.
Verify the sync engine's trigger behavior before adding sync. A partial import can
contain receipts before charges, and concurrent valid offline saves can create credit.
