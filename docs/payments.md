# Payments

## Ledger and coverage

The ledger is authoritative. Receipts belong to patients, not appointments.
Coverage is calculated from the full patient ledger, oldest obligation first;
receipts and negative adjustments cover charges and positive adjustments. The app
does not store receipt-to-charge allocations because the doctor should not have to
manage them. This is a derived view, not a saved appointment payment status.

Adjustments change debt without recording treatment fees or cash movement. They
support opening balances and incomplete history. An unknown payment method does
not mean cash, and net cash flow includes capital expenses, so it is not profit.

## Balances and dates

A complete local save must leave every affected patient's current balance
nonnegative. Intermediate credit is allowed so related corrections can succeed in
one transaction. Historical balances remain signed: a receipt can precede its
charge. Backdated changes alter past reports; creation timestamps are not an edit
audit trail.

Financial days use the Gregorian calendar in Asia/Kolkata regardless of device
settings. A balance through a date includes that whole clinic day. Known-balance
corrections must read history inside the transaction because screen totals can be
stale. Financial arithmetic must fail on overflow rather than change an amount.

Cancellation keeps linked charges. Financial history prevents patient deletion
even when settled; linked charges prevent appointment deletion or patient changes.
Schedule changes must not erase or reassign the clinic's financial history.

Appointment completion reads the scheduled status, patient, and linked charges in
the same transaction as the ledger batch and status update. It rejects repeat
completion, changed patients, and multiple linked charges. This keeps a stale or
competing request from recording another receipt. The entered payment replaces
the linked charge amount, or removes the charge for zero. Existing receipts stay
unchanged, so ledger validation can reject either operation.

## Derived balances

Current balance summaries are rebuildable, device-local data maintained by ledger
triggers. They allow temporary credit and partial imports. Rebuild for repair or
imports that bypass triggers, not on each read or launch. SQLite backups retain
these summaries; normal restore does not rebuild them.

Future sync must apply entries with summary triggers active and exclude summaries
from sync. Valid offline saves can produce credit when combined, so local
nonnegative-balance checks do not establish a cross-device guarantee.
