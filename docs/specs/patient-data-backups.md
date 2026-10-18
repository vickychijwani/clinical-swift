---
status: pending
---

# Patient data backups

## Purpose

Protect critical clinic records from device loss or database failure without a daily manual action.

## Backups

- Back up all Clinical records once daily, including all patients, appointment states, unavailable-time blocks, and historical records.
- Use Google Drive as the only remote destination. Store dated backups in an unshared, visible `Clinical Backups` folder in the connected Google Account.
- Keep 30 days of backups. Always retain the latest successful backup, even if older. Failed work must not remove usable backups.
- Report success only after the backup reaches Drive. Retry failures automatically without blocking clinic work.

## Settings and status

- Provide a small Settings sheet on Schedule and Patients. Place its button immediately left of the creation controls, with a separate Liquid Glass background. Creation controls stay at the right edge.
- Show backup status, the last successful backup time, the connected Google account, and connect/reconnect controls.
- Distinguish running, waiting, successful, and needs attention. Explain problems such as missing authorization, full storage, or overdue backups.
- Show a warning badge on Settings while a backup problem needs attention. Opening Settings does not clear the problem. Normal backup activity does not show a warning badge.

## Recovery

- Support documented, developer-assisted recovery from a selected backup, including when damaged or missing local data prevents normal app startup.
- Restore all saved clinic records. Reject invalid or unsupported backups before replacing current data, and allow recovery from an interrupted restore.
- Recovered records must work in Clinical and its widgets.

### Calendar

- Calendar events remain in iCloud; they are not part of the backup. Recovery uses the same iCloud account and clinic calendar, including on a replacement phone.
- Reconcile linked appointments and blocks for the previous seven calendar days and all future dates, measured from the restore date. Leave older Calendar events unchanged; all historical Clinical records are still restored.
- Make eligible linked events match the restored schedule, even when Calendar has newer values. Do not wait for another Clinical edit or import Calendar values into Clinical.
- Reuse existing events when found; create missing events when needed. Cancelled or deleted items must not create events. Retry failures automatically without requiring individual operator action or blocking other records.

## Release checks

Before release, automated checks must verify backup contents and validity, both locally and after upload to and download from real Google Drive. A failed or unavailable check blocks release. Keep backup checks separate from ordinary development tests.

## Accepted limits

- Changes after the latest successful backup can be lost. Device scheduling, network access, authorization, and storage can delay backups beyond 24 hours.
- Recovery requires the connected Google Account. Full Google storage pauses new uploads until resolved.
- Delayed iCloud sync can cause duplicate Calendar events. Events created only after the backup may remain after restore. Unrelated Calendar events remain unchanged.
- Backups do not provide cross-device Clinical record sync.

## Future scope

- Full backup status and history screens.
- User-facing restore controls and a recovery screen for database failure.

Implementation details belong in [the plan](../plans/patient-data-backups.md); operator instructions belong in [the recovery procedure](../patient-data-restore.md).
