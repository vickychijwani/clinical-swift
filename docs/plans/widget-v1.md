# Implementation plan for Widget v1

## Target and shared database

- Add a large-only WidgetKit extension and App Group `group.in.bitehaus.clinical` to both targets.
- Open `SQLiteData.db` directly inside the App Group from the main app.
- Do not migrate, inspect, or preserve the existing private-container database. The unreleased app may start with a fresh shared database.
- The app remains responsible for creating and migrating the database. The widget opens it read-only and shows “Open Clinical to load appointments” if it does not exist yet.
- Reload the widget once after app database initialization, then retain a GRDB `DatabaseRegionObservation` covering `appointments` and `patients` to request timeline reloads after relevant commits.

## Shared appointment presentation

- Move `AppointmentCard`, `Appointment`, `AppointmentStatusPresentation`, and their minimal typography/model dependencies into a synchronized shared source root compiled by both the app and widget targets.
- Preserve `AppointmentCard`’s existing API and timeline behavior.
- Render widget appointments directly with:

```swift
AppointmentCard(appt: appointment)
    .frame(maxWidth: .infinity)
    .frame(height: plannedRowHeight)
```

- Compose the widget’s required thick accent leading border around the reused card rather than duplicating its internal styling.
- Move the unknown-patient fallback behind one shared semantic helper so the widget and app cannot diverge.

## Widget data and timeline

- Query non-cancelled appointments from today through the end of the third consecutive date, joining patient names and sorting by start time.
- Filter to `end > timelineEntry.date`, including in-progress appointments and excluding appointments ending exactly at that time.
- Always construct today, tomorrow, and the day after tomorrow; the layout planner decides how many consecutive sections fit.
- Refresh at the earlier of the next eligible appointment end or local midnight. Database commits trigger additional reload requests.
- Use a static, non-configurable `.systemLarge` widget.

## Layout

- Implement a pure `WidgetLayoutPlanner` using these centralized metrics:
  - Standard row: 44 points.
  - Permitted row range: 40–48 points.
  - Header: 20 points.
  - Header-to-content spacing: 2 points.
  - Row spacing: 4 points.
  - Section spacing: 6 points.
- Earlier sections must fit completely before admitting the next date. Only the final visible section may truncate and use its last row for `N more appointments`.
- Calculate one shared row height so the final visible row reaches the bottom of the usable widget area.
- Use standard WidgetKit content margins and one scoped geometry measurement; never use screen bounds.
- Date-section links sit behind appointment links so appointment selection wins. Headers, empty messages, overflow summaries, and residual section space open that section’s date.

## Routing

- Extend `ClinicalURL` with:
  - `clinical://appointments/{uuid}`
  - `clinical://schedule?date=YYYY-MM-DD`
- Appointment links reuse `Router.openExternalDetails(.appointment(id))`.
- Add a router-owned `ScheduleDateRequest`; `ScheduleView` consumes it and updates `ScheduleModel.selectedDate`.
- Keep the existing booking URI unchanged.

## Testing and documentation

- Remove all legacy-database migration tests from the previous plan.
- Test:
  - Shared-container database creation and widget behavior before the first app launch.
  - Query eligibility, ordering, patient fallback, calendar boundaries, and Sunday messages.
  - Layout across dense, sparse, empty, and overflow schedules.
  - Equal `AppointmentCard` heights, exact bottom alignment, consecutive sections, and overflow counts.
  - Deep-link parsing and router request consumption.
- Add widget previews covering dense, sparse, Sunday, overflow, unknown-patient, dark/light, placeholder, and unavailable-database states.
- Document App Group ownership, read-only widget access, timeline invalidation, shared `AppointmentCard` ownership, and layout invariants in `docs/widgets.md`.
- Mark `docs/specs/widget-v1.md` as implemented only after the implementation is complete.
- Builds, tests, previews, simulator, and device verification remain opt-in and won’t be run without explicit authorization.
