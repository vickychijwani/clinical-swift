# Payments data model implementation plan

Status: implemented. The data layer and required checks are complete. The source feature
specification is [payments data model](../specs/payments-data-model.md). Durable rules are in
[payments](../payments.md). Payment screens remain a separate work item.

## Agreed scope

- Implement the data layer: domain types, database storage, write operations, queries, balance and
  coverage calculations, and unit tests. Payment screens come later.
- Block patient deletion while that patient has financial entries, including when the balance is
  zero. A zero balance does not mean that the history can be discarded.
- Reject a complete local save that leaves an affected patient's current balance below zero. Do
  not change an entered amount to make the save pass.
- Validate the complete transaction, including edits and deletions. A charge correction and a
  receipt correction can succeed together when the resulting current balances satisfy the rule.
- Allow negative intermediate balances within a transaction. Check final current balances after
  the complete batch, independent of recording timestamps or write order.
- Permit negative historical balances. Calculate reports from the dated entries and show signed
  results; do not reject backdated changes or change negative historical totals to zero.
- Maintain current balances in a derived `patientBalances` table with database triggers. Entries
  remain authoritative; summaries can be rebuilt and are excluded from future cross-device sync.
- Block appointment patient reassignment and physical deletion while linked charges exist.
  Cancellation keeps the charges; any financial correction is a separate explicit action.
- Allow several charges per appointment. Derive its total from all linked charges.
- Edit known charges and receipts to correct mistakes. Reserve adjustments for opening balances
  and corrections to incomplete history; they change debt without creating new treatment fees.
- Allow direct entry edits and deletion, subject to the current-balance rule. A full edit
  history is outside this version.
- Reject future financial dates for all entry kinds.
- Use the Gregorian calendar and `Asia/Kolkata` time zone for financial dates, independent of device
  settings. Store `entryDate` as the start of the clinic calendar day through the existing SQLite
  `Date` mapping. Keep recording timestamps as full instants.
- Allow charges linked to scheduled, completed, and cancelled appointments. Appointment status
  does not create, remove, or move a financial obligation.
- Require a patient for `patientFees` receipts. All other receipt categories have no patient link.
- The app has no production deployment. Existing development data can be discarded during schema
  changes. Data-preserving upgrades and compatibility with old development snapshots are outside
  this work.

Patient refunds, unapplied current credit, payment screens, and full edit history are outside this
version. No new third-party framework is required.

## Current code constraints

- `ClinicalModels` owns domain values. `ClinicalPersistence` owns records, migrations, queries, and
  transactional writes. Both must remain compatible with Linux.
- The app is the only migration and write owner; the widget remains a read-only client.
- `AppointmentBookingModel` currently updates `patientID` directly. The schema must prevent that
  path from breaking linked charge ownership, and the app must report the rejection clearly.
- Existing patient deletion cascades to appointments. The new financial references must block
  deletion before that cascade can discard appointment context.
- Backups capture the SQLite database and its migration list. Entries and their derived summaries
  belong in that same snapshot. No separate backup format is required.
- A charge deliberately has patient and appointment foreign keys. This supports patient ledgers
  and appointment tracing, but limits future record sharing as described in `docs/persistence.md`.
  The specification accepts that tradeoff.

## Implementation sequence

### 1. Establish model validation and financial dates

The pending Markdown specification now contains the agreed rules and kind/field validation table.
Keep its status pending until implementation is complete. Do not read or change its HTML companion
unless the user asks for that work.

Use the validation table as the contract for domain validation and database row checks. Preserve
whole-rupee integer amounts, blank-note normalization, stable creation timestamps, editable
financial dates, and fixed category reporting groups. A missing payment method remains unknown.

Add one payments-owned financial-date helper in the package. Use a fixed clinic calendar and the
existing registered date dependency for the current day. Do not change scheduling calendar
behavior as part of this work. Normalize dates before validating or storing them; compare clinic
dates when rejecting future values. Reuse the existing date helpers where they fit.

### 2. Add domain values and calculations

Add `AccountEntry` under the payments feature in `ClinicalModels`. Keep its nested kind, category,
and payment-method enums with their owner. Keep SQLite storage details in `ClinicalPersistence`.
Use a small set of cohesive files, such as `payments/AccountEntry.swift` and
`payments/PatientLedger.swift`, rather than one file per small enum or result type.

Provide pure calculations for patient balances and oldest-first coverage. Order obligations by
financial date, creation timestamp, and UUID string. Include positive adjustments as obligations
and negative adjustments as coverage. Distinguish coverage from money received. Aggregate linked
charges to produce appointment totals without storing a separate appointment fee or payment status.
For a historical result, first exclude entries after the selected financial date. For current
appointment coverage, use the full current patient ledger rather than only that appointment's
entries. Coverage totals must agree with the patient balance after patient-level obligations are
included.

Historical results can contain unallocated credit. Keep each charge's coverage between zero and
its amount, and preserve the unallocated amount so the historical result agrees with its signed
balance. Current results from valid local saves have no excess credit.

Validate final current balances for all affected patients, including both patients when an entry
moves between them. Use the trigger-maintained summary instead of scanning each patient's dated
history on writes. Keep pure ledger sums for reports, rebuild verification, and tests. Use checked
integer arithmetic; invalid amounts or totals must produce an error rather than trap or wrap.

### 3. Add the database schema

Add an `accountEntries` table using the simplest development schema change. A new migration is
acceptable, but unreleased migrations can be revised and development databases can be reset.
Do not add data-conversion code or preserve old development schemas solely for compatibility.
Use the existing UUID primary-key policy and standard `createdAt` and `updatedAt` columns. Map
domain `createdDate` to record `createdAt`. Append-only migration rules apply after production
deployment.

Keep record mapping in `AccountEntryRecord.swift`. Use stable explicit storage strings for enums;
report an invalid stored value rather than silently omitting a financial entry from a total.

Add row constraints for kind, amount, categories, payment methods, and reference rules. Use
restrictive foreign keys for patient and appointment deletion. Check charge-to-appointment patient
matching on entry insert and update, and block appointment patient reassignment while linked
charges exist. Enforce these reference rules in SQLite so direct writes cannot break them.

Use indexes for patient history, appointment charges, and financial-date queries. Several charges
can reference one appointment; do not add a unique appointment-charge constraint.

Add `patientBalances` with a patient UUID primary key, integer balance, and standard record
timestamps. Keep it separate from `PatientRecord` and the `Patient` domain value. A patient with
no summary row has zero balance. Summary references can cascade on patient deletion; the ledger
references remain restrictive so a derived summary alone cannot block deletion.

Use `AFTER INSERT`, `AFTER UPDATE`, and `AFTER DELETE` entry triggers to maintain signed totals.
An update removes the old contribution and adds the new one, including when kind or patient
changes. Expenses and receipts without a patient do not contribute. Guard integer overflow in
summary arithmetic. Index positive balances for the patients-who-owe query. Do not put a
nonnegative row constraint on the summary: a valid complete save can have a negative intermediate
balance.

Provide a transactional rebuild that replaces summaries with grouped ledger sums. Run it when
adding summaries to an existing ledger, and expose it for repair or an import that does not replay
entry writes. Do not add grouped totals to existing summaries or rebuild on every list read or
app launch. Test rebuild and trigger updates against the same ledger calculation.

### 4. Add transactional write operations

Provide create, edit, delete, and combined-save operations in `ClinicalPersistence`. Read the
current records, check references, apply the proposed changes, and validate the resulting current
patient balances within one database transaction. Roll back the whole operation on failure.

Keep this boundary in `AccountEntryPersistence.swift`. Use one batch of inserts, updates, and
deletes instead of a separate service for each entry kind. Read existing rows before mutation so
both the old and new patients enter the affected set. Preserve creation time from the stored row.

Omit zero-valued new entries in combined workflows. Reject an edit to zero; use explicit deletion
to remove an existing entry. Preserve entry identity and creation time on edits. Report missing
records and invalid references as explicit errors. Creating a duplicate entry ID must fail rather
than overwrite an existing payment.

Combined saves must support charge plus receipt and adjustment plus receipt without separate
commits. Provide a database-scoped batch operation and a writer wrapper, following the existing
persistence style. The batch can run after appointment creation in the same outer write transaction
when that workflow is added. Do not add financial input controls in this work.
The database-scoped operation must roll back its own changes on error, even if an outer caller
catches that error; use a savepoint. A future combined appointment workflow must propagate the
failure so its outer transaction also rolls back.

For an opening balance or incomplete-history correction, read the balance through the selected
financial date inside the write transaction and calculate the adjustment from that value.
Calculate it before adding a receipt entered in the same action. Do not use a balance previously
loaded by a screen. Omit a zero difference and reject a negative target balance. Known charge or
receipt mistakes use the existing entry's edit operation instead of a balance adjustment.

Read each affected patient's final summary at the end of the complete batch and reject a negative
current balance. The summary triggers run on every mutation but do not reject intermediate credit.
Do not scan historical running balances as part of save validation. Row constraints and reference
guards remain in SQLite. Supported local financial writes must use the batch boundary; raw SQL
and record writes are not a financial mutation API.

Future sync must apply ledger changes with the summary triggers installed. A fresh device builds
summaries as entries arrive. Do not treat an initial partial import as complete or reject incoming
receipts solely because their charges have not arrived yet. Verify the chosen sync engine's trigger
behavior and define conflict handling before adding sync. Concurrent offline payments can produce
credit even when both original local saves passed validation. This plan does not implement sync.

Update the existing appointment write paths only where needed to enforce the agreed reference
rules. A check in a future payments screen is insufficient because appointment edits already
exist.

### 5. Add read queries

Expose queries for patient history, balance through a selected financial date, appointment charges,
and the full patient ledger needed for coverage. Period reports use financial dates and clinic
calendar boundaries, not recording timestamps. Use inclusive start and exclusive end boundaries.

Use observed summary joins for current balances, the `balance > 0` patient filter, and total
outstanding balances. Provide the data queries in this work; patient-list controls remain later
UI work. Join at most one summary per patient to the existing patient query, which also joins
appointments. Do not sum raw ledger entries across appointment rows because that duplicates
contributions. Outstanding balances do not predict payment dates or fees for work not yet charged.

Provide receipt and expense totals by category, derived reporting group, and payment method. Keep
charges and adjustments out of cash-flow totals. Net cash flow includes capital expenses. Support
previous-note suggestions within a selected category without introducing payee records.

Keep query selections behind the persistence boundary and return domain read models. Make queries
suitable for SQLiteData observation so later screens do not need a manual cache.
Keep query code in `AccountEntryQueries.swift`. Include an unknown-method group when the stored
payment method is absent.

### 6. Test invariants and integration boundaries

Use package tests for domain validation, record mapping, fresh schema creation, database constraints,
transaction rollback, calculations, and query boundaries. Add app unit tests only for changes to
existing app-owned appointment writes.

Required cases include:

- Each valid and invalid kind/field combination; zero and signed amounts; blank notes.
- Stable creation times and integer overflow handling.
- Explicit errors for invalid stored enums; duplicate IDs that do not replace entries.
- Partial and exact payments, positive and negative adjustments, deterministic coverage ties,
  and backdated changes.
- Opening-balance and incomplete-history adjustments that affect debt and coverage without
  increasing treatment charges or cash totals; known charge and receipt corrections use edits.
- Overpayment rejection, paid-charge reduction or deletion, and valid combined corrections.
- An accepted receipt backdated before its supporting charge when the final current balance is
  nonnegative; negative historical balances remain visible in reports.
- Coverage for a negative historical balance, with unallocated credit and no overcovered charges.
- Same-day combined entries, temporary negative balances, and patient moves that check both totals.
- Trigger summaries matching ledger sums after inserts, edits, kind changes, patient changes,
  deletion of the last entry, rollback, and rebuild. Cover expenses and unlinked receipts too.
- Positive-balance filtering, zero for a missing summary, and observed updates after ledger writes.
- Rejection of patient deletion with financial history, including a zero balance.
- Appointment reference mismatches, multiple charges, blocked deletion and patient reassignment,
  and cancellation that retains charges.
- Future-date rejection and edits to zero that require explicit deletion.
- A known-balance correction based on the current stored history, with a paired receipt.
- A failed database-scoped batch that leaves no changes even when its caller catches the error.
- Clinic midnight and period boundaries with a device time zone different from the clinic's.
- A fresh database creates the required tables, indexes, triggers, and reference guards.
- Backup and restore of entries through the existing SQLite snapshot path.

Extend `clinical-swiftBackupTests/BackupFixture.swift` with valid financial entries and their
trigger-maintained summaries. Its existing snapshot comparison checks every table and field. Add
explicit restored-entry and summary assertions in
`BackupSnapshotTests.swift`, where restore checks currently select patients and appointments.
Use the current schema for backup tests. Omit tests for preserving pre-payments development data
and restoring older development snapshots.

Use `make data-test` during package development as needed. For final verification, run
`scripts/check_architecture.sh`, `make test`, and `make backup-test`. `make test` includes the
package tests, so a separate final `make data-test` is unnecessary. The app tests cover the
existing appointment editor error path; the backup tests need no network credentials. No UI tests
are needed. Review deleted Swift comments and run
`/bin/sh .codex/hooks/stop.sh --check </dev/null` before completion.

### 7. Record durable rules

Add a short payments architecture guide for current-balance validation, signed historical reports,
date semantics, reference rules, the transaction boundary, summary rebuilds, sync boundaries, and
derived coverage. Add it to the root documentation map.
Update existing persistence and appointment guides where the new rules affect their invariants.
Mark the feature specification implemented only when its agreed data-layer scope is complete.

## Completion conditions

- A fresh database starts with the required schema. Existing development data can be reset.
- Invalid entries and broken references cannot enter through supported writes.
- No successful supported local save leaves an affected patient's current balance below zero.
- Negative historical balances are accepted and reported accurately.
- Current summaries agree with the ledger after every committed mutation and can be rebuilt.
- Financial history survives schedule changes according to the agreed rules.
- Queries and calculations derive balances, coverage, and cash reports from entries.
- Required tests pass, and payment screens remain a separate work item.
