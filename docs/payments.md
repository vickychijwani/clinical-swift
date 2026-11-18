# Payments

## Ledger and coverage

The patient ledger is authoritative. Receipts belong to patients. Apply receipts
and negative adjustments to charges and positive adjustments, oldest obligation
first. Derive coverage from the full ledger; the doctor should not have to manage
receipt allocations or appointment payment states.

Adjustments support opening balances and incomplete history without recording
treatment fees or cash movement. An unknown payment method does not mean cash.
Net cash flow includes capital expenses, so it is not profit.

## Balances and dates

A completed local save must leave affected patients' current balances nonnegative.
Allow temporary credit while applying related changes together. Historical
balances can be negative because a receipt can precede its charge. Backdated
changes alter past reports; creation timestamps are not an edit audit trail.

Financial days use the Gregorian calendar in Asia/Kolkata, regardless of device
settings. A balance through a date includes that whole clinic day. Corrections
must use current history, not screen totals. Reject arithmetic overflow.

Keep linked charges on cancellation. Financial history prevents patient deletion,
even when settled. Linked charges prevent appointment deletion or patient changes:
schedule changes must not erase or reassign financial history.

Completion and its financial changes must succeed together. Stale or repeated
requests must not record another receipt. Changing a charge must preserve existing
receipts and satisfy the same balance rules as other ledger edits.

## Derived balances

Balance summaries are derived, device-local data. The ledger remains authoritative
for repair and imports; summaries must not be synced.

Valid offline saves can produce credit when combined. The local balance rule is
not a cross-device guarantee; future sync must account for this.
