# Payments

## Ledger and coverage

The patient ledger is authoritative and receipts belong to patients. Apply
receipts and negative adjustments to charges and positive adjustments, oldest
obligation first, so the doctor never manages receipt allocations or appointment
payment states.

Adjustments support opening balances and incomplete history without recording
treatment fees or cash movement. An unknown payment method does not mean cash.
Net cash flow includes capital expenses, so it is not profit.

## Balances and dates

A completed local save must leave affected patients' current balances
nonnegative; temporary credit is allowed only within one atomic multi-change
save. Historical balances can be negative because a receipt can precede its
charge. Backdated changes alter past reports; creation timestamps are not an
edit audit trail.

Financial days follow the [clinic date rule](../AGENTS.md#architecture).
Corrections must read current history, not screen totals.

Keep linked charges on cancellation. Financial history prevents patient
deletion, even when settled. Linked charges prevent appointment deletion or
patient changes so schedule edits cannot erase or reassign financial history.

Completion and its financial changes must succeed together; stale or repeated
requests must not record another receipt.

## Derived balances

Balance summaries are derived, device-local data. The ledger remains
authoritative for repair and imports; summaries must not be synced.

Valid offline saves can produce credit when combined. The local balance rule is
not a cross-device guarantee; future sync must account for this.
