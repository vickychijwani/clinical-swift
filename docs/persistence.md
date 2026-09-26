# Persistence Architecture

This document captures local SQLite persistence constraints future agents are likely to break when adding storage-backed features.

## Overview

- For persistence we use SQLiteData (pointfreeco/sqlite-data)
- For SQL queries we use StructuredQueries (pointfreeco/swift-structured-queries)

## Invariants

Although sync is not yet implemented, note these invariants related to sync (applicable to CloudKit and any other sync engines like PowerSync):

- Primary keys must be globally unique identifiers, such as UUID, and cannot be an autoincrementing integer. That would make it possible for two devices to create a record with id: 1, leading to irreconcilable conflict on sync. Further, a NOT NULL ON CONFLICT REPLACE clause must be specified.
- Uniqueness constraints are prohibited, to allow distributed creation of records.
- Each synchronized table must have a single, non-compound primary key
- Certain migrations are simply not allowed with sync: removing columns, renaming columns, and renaming tables
- If needed, foreign key constraints CAN be enabled and you CAN use ON DELETE actions to cascade deletions
- Conflicts are handled automatically using a “last edit wins” strategy for each column of the record
- If possible avoid creating many-to-many relationships or records with multiple foreign keys, as that forecloses the possibility of sharing data with other users - this might become a blocker for multi-user usecases in future (e.g., separate accounts for staff and doctors). If you need to break this guideline, clearly tell the user why you've broken it, AND why the guideline exists in the first place, so they can evaluate the trade-off for themselves.

General invariants:

- The live database resides in the `group.in.bitehaus.clinical` App Group so the WidgetKit
  extension can read it. The app remains the only migration and write owner; extensions open a
  coordinated read-only pool and never create or migrate the database.
- `appointmentCalendarSync` is device-local integration metadata even though it lives beside the
  app's domain tables so database triggers can enqueue Calendar work transactionally. Never include
  it in future CloudKit or other cross-device sync: EventKit identifiers belong to one device's
  event store. Its missing appointment foreign key is deliberate so deletion work survives patient
  cascade deletion.
- Shared database connections use persistent WAL mode and `NSFileCoordinator`. Do not replace this
  with an uncoordinated read-only connection: read-only processes cannot recreate missing WAL/SHM
  sidecars, and cross-process opening has additional file-locking constraints.

- Domain structs remain separate from database records. `Patient` and `Appointment` are UI-facing values; `PatientRecord` and `AppointmentRecord` define the SQLite boundary.
- Typed read selections should nest complete record values alongside aggregates or joined records. This keeps query projections aligned with table schemas and avoids duplicating record construction field by field.
- Query builders passed to SQLiteData async fetch APIs must return `some Statement<...> & Sendable`. This makes the opaque statement's conformance safe to use across SQLiteData's concurrent boundary under the app's default MainActor isolation.
- StructuredQueries expressions can overwhelm Swift's type checker after a join. Apply single-table filtering, grouping, and ordering before the join when semantics allow, and use one named intermediate query to establish the simpler generic type.
- `collate` requires a non-optional string expression. For nullable text, use `column.ifnull("").collate(...)`; prefer `ifnull` over the heavily overloaded query `??` operator to reduce compiler work.
- Every record table has standard `createdAt` and `updatedAt` fields.
- Appointments reference patients by `patientID`. Do not store patient names in appointments as the source of truth because patient names can change.
- Core domain structs do not store derived fields, e.g., `Patient` does not store fields like `nextAppointmentDate`. In that example, derive appointment rollups into list/read models from future appointment rows so they cannot drift from the schedule.
- Storage-backed read models that must stay current with appointment writes or future sync should use SQLiteData observed queries (`@FetchAll`, `@FetchOne`, or `@Fetch`) instead of explicit caches. Manual caches force every write path, including future background sync, to remember change-notification events and are easy to leave stale.
- Persisted appointment status is a one-way state machine: scheduled appointments may become completed or cancelled, while completed and cancelled appointments are terminal. Status-only self-transitions are idempotent and must not advance `updatedAt`.
- Appointment status changes must read, validate, and write within one database transaction. Do not perform transition checks only against a value previously loaded by the UI because that can overwrite a newer terminal state.
- `draft` is presentation-only appointment state. Persistence construction and mutation APIs must reject it rather than encoding a placeholder value.
- Normal appointment reads exclude cancelled rows by default. Cancelled records remain stored for audit use; a future administrative query must opt into them explicitly.
- “Next appointment” metadata uses only future scheduled rows. Completed appointments remain historical records but are not upcoming work.
- Migrations are append-only after release. Do not edit old migration SQL once users may have run it because existing databases replay migrations by name.
- In `#sql` expressions, never interpolate a runtime value as `\(value)`. Use `\(bind: value)` for non-optional values and an explicitly typed `\(#bind(value, as: Value?.self))` for optional values; bare interpolation is deprecated and can produce an optional value's debug description instead of a database bind.
- Large binary blobs of data (BLOB type) MUST be in their own tables to avoid performance issues when querying non-blob data

## Do Not Reintroduce

- Do not make database records drive presentation fallbacks. e.g., Unknown-patient display names belong in the domain/UI layer, not in stored patient names.
- Do not pass SQL selection rows through patient UI. Map them to read models first so SQLite query shape stays behind the persistence boundary.
- Do not scatter cancellation filters through view models. Enforce normal visibility in persistence queries so future views cannot accidentally expose retained cancelled rows.

## Edge Cases

- Unknown patients can have `name == nil`; joins should use `Patient.unknownDisplayName` only for display rows.
- Deleting a patient cascade deletes their appointments.
- Debug sample data is seed data only for fresh debug databases. Release databases start empty.
