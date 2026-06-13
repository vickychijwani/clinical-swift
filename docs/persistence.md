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

- Domain structs remain separate from database records. `Patient` and `Appointment` are UI-facing values; `PatientRecord` and `AppointmentRecord` define the SQLite boundary.
- Every record table has standard `createdAt` and `updatedAt` fields.
- Appointments reference patients by `patientID`. Do not store patient names in appointments as the source of truth because patient names can change.
- Core domain structs do not store derived fields, e.g., `Patient` does not store fields like `nextAppointmentDate`. In that example, derive appointment rollups into list/read models from future appointment rows so they cannot drift from the schedule.
- Migrations are append-only after release. Do not edit old migration SQL once users may have run it because existing databases replay migrations by name.
- Large binary blobs of data (BLOB type) MUST be in their own tables to avoid performance issues when querying non-blob data

## Do Not Reintroduce

- Do not make database records drive presentation fallbacks. e.g., Unknown-patient display names belong in the domain/UI layer, not in stored patient names.
- Do not pass SQL selection rows through patient UI. Map them to read models first so SQLite query shape stays behind the persistence boundary.

## Edge Cases

- Unknown patients can have `name == nil`; joins should use `Patient.unknownDisplayName` only for display rows.
- Deleting a patient cascade deletes their appointments.
- Debug sample data is seed data only for fresh debug databases. Release databases start empty.
