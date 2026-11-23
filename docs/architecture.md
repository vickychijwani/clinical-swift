# Architecture boundaries

Keep shared models and persistence independent of Apple-only services so they can
run on Linux. The [dependency checker](../scripts/check_architecture.swift) enforces
package boundaries. See [persistence](persistence.md) for database ownership and
cross-process rules.

## Clinic date and locale

All dates, times, and formatted text in the app and widget use the Gregorian
calendar in `Asia/Kolkata` with the `en_IN` locale (`ClinicDate`), regardless of
device settings. Storage, backup, and telemetry timestamps remain UTC ISO-8601.
The [ClinicDate checker](../scripts/check_clinic_date.swift) rejects device
calendar, locale, and time-zone defaults in production sources.
