# Payments

## Domain and storage

Keep one account-entry table because all kinds share identity, dates, notes, backup,
and the create, edit, and delete lifecycle. Patient history, cash reports, and batch
saves combine kinds. Several tables would also work, but add dispatch and combined
queries for these few fields. Nullable columns and conditional constraints stay at
the record boundary. Reads must reject invalid stored combinations.

Swift entries use four explicit cases. A charge carries its patient and optional
appointment. A receipt carries a patient source or another incoming source. Patient
sources imply patientFees. Expenses admit only operating and capital categories.
Adjustments carry only their patient. Kind-specific fields are derived, so a kind
change must supply the new case's required values. Amounts and dates still need
validation; writes also check the current date and database references.

This storage choice is separate from derived coverage. Automatic coverage avoids
manual allocation work. Separate types or tables would not require manual allocation.

## Ledger and local saves

Account entries are the source for debt, coverage, and cash reports. Amounts are
whole rupees. Charges, receipts, and expenses must be positive. Adjustments are
signed and nonzero. Blank notes become nil. An absent payment method is unknown.

All local financial writes use the account-entry batch boundary, including edits
and deletion. It reads old ownership, checks fields and references, applies the
complete batch, then checks each affected patient's current summary. A patient
move checks both patients. The final balance must be nonnegative. Intermediate
credit is allowed, so charge and receipt corrections can succeed together.
The database-scoped batch uses a savepoint: catching its error in an outer write
cannot leave partial changes. A future appointment-and-payment action must let
that error leave its outer transaction so the appointment also rolls back.
Raw SQL and record writes are not a supported financial mutation API.

New zero entries are omitted. Editing to zero is an error; use explicit deletion.
Edits preserve identity and creation time. Duplicate creation must fail rather
than replace financial history. Known mistakes use entry edits. Opening balances
and incomplete-history corrections use adjustments so they do not create treatment
fees or cash. A known-balance correction reads the balance through its selected
date inside the write, before adding a paired receipt. It cannot use screen state.
Financial arithmetic must fail on integer overflow.

## Dates and reports

Financial dates use the Gregorian calendar in Asia/Kolkata, independent of device
settings. Store the start of the clinic day with the existing SQLite Date mapping.
Recording timestamps remain full instants. Normalize before validation; reject
future clinic dates. Periods include their start day and exclude their end day.
A balance through a selected date includes that whole clinic day.

Historical balances are signed. A receipt backdated before its charge is valid
when the final current balance is nonnegative. It can create historical credit;
do not reject it or change the historical result to zero. Backdated edits change
past reports. Recording timestamps do not provide an edit audit trail.

Cash reports include receipts and expenses only. Net cash flow includes capital
expenses and is not profit. Categories determine reporting groups. Notes can
supply category-scoped suggestions; they are not separate payee records.

## References and coverage

SQLite guards charge ownership as well as the supported write API. A linked charge
must belong to the appointment's patient. Several charges can link to one
appointment. Charges can link to any stored appointment status. Cancellation
keeps charges. Physical deletion and patient reassignment are blocked while
charges remain linked. A patient with financial history cannot be deleted even
when the balance is zero. A derived summary alone does not block patient deletion.

Receipts belong to patients, not appointments. A receipt uses patientFees if and
only if it has a patient. Other incoming categories and all expenses have no
patient. Charge and adjustment categories and payment methods are absent.

Derive oldest-first coverage from the full patient ledger. Order obligations by
financial date, creation time, then UUID string. Positive adjustments take their
place with charges. Receipts and negative adjustments cover these obligations;
only receipts count as money received. Appointment totals include all linked
charges. Coverage cannot exceed an obligation. Historical excess coverage remains
unallocated credit, so outstanding obligations minus that credit equals the
signed balance. No allocation or appointment payment-status record is stored.

## Summaries, observation, and sync

Entry triggers maintain patientBalances within each transaction. A missing summary
means zero. Do not constrain summaries to nonnegative values: temporary credit
and partial future imports need signed totals. Read final summaries for local-save
validation. Use observed summary joins for current balances and positive-balance
filters. Join one summary per patient; summing ledger rows across appointments
would multiply debt. Historical reports and coverage still read entries.

Rebuild summaries transactionally from grouped ledger sums for repair or an import
that bypasses entry writes. Replace summaries instead of adding to them. Do not
rebuild on every list read or launch. Entries and summaries share the existing
SQLite backup and restore snapshot.

Future cross-device sync must exclude summaries and apply entries with triggers
installed. A new device builds summaries as entries arrive. Do not treat a partial
initial import as complete or reject receipts whose charges have not arrived.
Verify the sync engine's trigger behavior and define conflicts before adding sync:
concurrent offline receipts can produce credit after valid local saves.
