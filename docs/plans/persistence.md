# Local SQLiteData Persistence Plan

## Summary
Add local on-device persistence using Point-Free’s `SQLiteData`, backed by GRDB migrations and observed queries. Persist patients and appointments through separate storage records, keep domain structs UI-facing, and wire the first app pass to read patients/appointments from SQLite plus save patients from `EditPatientView`.

SQLiteData integration points: `@Table`, `@FetchAll`, `prepareDependencies`, `defaultDatabase`, and SQL migrations from https://github.com/pointfreeco/sqlite-data.

## Key Changes
- Add Swift package dependency `https://github.com/pointfreeco/sqlite-data`, using the `SQLiteData` product in app and test targets.
- Add `clinical-swift/persistence/Database.swift` with `appDatabase() throws -> any DatabaseWriter`, `DatabaseMigrator`, debug-only query tracing, and debug-only first-launch sample seeding.
- Configure `ClinicalApp.init()` with `prepareDependencies { $0.defaultDatabase = try! appDatabase() }`.
- Keep domain models separate from storage records and add explicit mapping helpers.

## Storage Model
- Add `@Table struct PatientRecord: Identifiable, Sendable` with:
  - `id: UUID`
  - `name: String?`
  - `phone: String?`
  - `dob: Date?`
  - `gender: String?`
  - `createdAt: Date`
  - `updatedAt: Date`
- Add `@Table struct AppointmentRecord: Identifiable, Sendable` with:
  - `id: UUID`
  - `patientID: PatientRecord.ID`
  - `startTime: Date`
  - `durationMinutes: Int`
  - `status: String`
  - `createdAt: Date`
  - `updatedAt: Date`
- Do not store `nextAppointmentDate` on `PatientRecord`; derive it from that patient’s future `AppointmentRecord` rows when reading patient list data.
- Use a foreign key from appointments to patients with `ON DELETE CASCADE`.
- Store `Gender` and `Appointment.Status` as stable string raw values at the record boundary.
- Add mappings:
  - `PatientRecord.init(_ patient: Patient, now: Date = .now)`
  - `Patient.init(_ record: PatientRecord)`
  - patient-list query rows map to a read model with `Patient` plus derived `nextAppointmentDate`
  - appointment query rows map to `Appointment(id:patientName:startTime:durationMinutes:status:)`.
- Update `Appointment` to accept a persisted `id` in its initializer instead of always creating `let id = UUID()`.

## App Integration
- Replace live sample patient/schedule injection with database-backed reads.
- In `PatientsView`, fetch patient rows plus each patient’s next future appointment date, then map the SQL row into a patient-list read model before existing section/search logic.
- In `ScheduleView`, fetch appointments for `selectedDate` by joining `AppointmentRecord` to `PatientRecord`, filtering by `startTime` within that local day, and mapping into existing `Appointment` values.
- Keep sample data for previews/tests and debug seeding only; Release starts empty.
- Wire `PatientsView` Add button to `EditPatientView`; on confirmation, validate `Patient`, insert `PatientRecord`, dismiss on success, and leave appointment CRUD for a later pass.

## Documentation
- Add `docs/persistence.md` covering:
  - domain structs stay separate from database records
  - appointments reference patients by `patientID`
  - `nextAppointmentDate` is derived from appointments, never stored on patient records
  - all records carry `createdAt`/`updatedAt`
  - migrations are append-only after release
- Add the persistence doc to `AGENTS.md` Documentation Map.
- Update `docs/patients.md` to note that unknown-patient fallback remains presentation-only and must not be stored as a fake name.

## Test Plan
- Add mapping tests:
  - blank patient name/phone normalization survives `Patient -> PatientRecord -> Patient`
  - `Patient.init(_ record:)` maps stored fields correctly
  - `Gender.other` and appointment statuses round-trip through storage strings
- Add database tests:
  - migrations create both tables
  - inserting a patient and appointments returns the correct derived `nextAppointmentDate`
  - schedule query joins appointment rows to patient display names
  - deleting a patient cascades appointments
  - patient save inserts valid patients and rejects missing name+phone
- Run hosted iOS `xcodebuild test`, then build the app target. Run SwiftLint too if installed.

## Assumptions
- Local-only means no CloudKit `SyncEngine`, no iCloud entitlements, and no remote schema.
- Debug builds seed sample patients/appointments into an empty database; Release starts empty.
- First implementation wires reads for patients/schedule plus patient creation only; appointment creation/editing is out of scope.
- Implementation should verify the resolved SQLiteData version before editing project dependency metadata.
