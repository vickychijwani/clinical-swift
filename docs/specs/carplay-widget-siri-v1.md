----
status: shelved
----

# Clinical in the Car: low-effort v1

## Summary

Build a CarPlay-compatible schedule widget and hands-free Siri actions now; do not build a dedicated CarPlay scene unless Apple grants an entitlement.

Clinical currently does not fit an approved CarPlay category. Apple explicitly says driving-task apps must help with the drive, while communication apps must provide messaging or VoIP. CarPlay support also lives inside the existing iOS app rather than a separate extension. An entitlement request is therefore the gating risk, not engineering feasibility. [Apple CarPlay Developer Guide](https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf), [CarPlay overview](https://developer.apple.com/carplay/).

| Deliverable | Effort | Production code | Test code | Complexity |
|---|---:|---:|---:|---|
| CarPlay-sized schedule widget | 1–2 days | 150–250 lines | 100–200 lines | Low |
| Hands-free schedule/book/reschedule/cancel Siri suite | 6–10 days | 700–1,200 lines | 500–900 lines | Medium–high |
| Locked-device handling, docs, smoke validation | 1–2 days | 50–150 lines | 100–200 lines | Medium |
| Recommended v1 total | 8–14 days | 900–1,600 lines | 700–1,200 lines | Moderate |
| Dedicated CarPlay UI, only after entitlement | +4–7 days | +500–850 lines | +250–450 lines | Moderate |

The Siri work is the majority of the lift because patient and appointment disambiguation, confirmations, background database writes, and stale-data handling must be reliable.

## Implementation Changes

### Shared appointment action boundary

- Introduce an internal `AppointmentCommandService` over the existing database, calendar, and clock dependencies.
- Support schedule lookup, booking, rescheduling, and cancellation without involving `Router` or SwiftUI.
- Refactor the existing booking model to reuse this write boundary so Siri and the iOS editor cannot develop different validation rules.
- Preserve existing invariants: overlaps and clinic-break bookings remain valid; clinic-hour validation remains shared; rescheduling and cancellation atomically verify that the appointment is still scheduled.
- Keep the existing foreground `BookAppointmentIntent` for compatibility with current Shortcuts. Add a distinct hands-free scheduling intent rather than silently changing existing shortcut behavior.

### CarPlay schedule widget

- Add `.systemSmall` alongside the existing `.systemLarge`; Apple supports system-small widgets in CarPlay without a CarPlay app entitlement.
- Give `.systemSmall` a dedicated glanceable layout showing the next two appointments across the existing three-day snapshot, plus an overflow count.
- Display patient identity as first name plus last initial. Leave the existing large widget unchanged.
- Make the small variant informational rather than link-driven. Without a CarPlay entitlement, widget links cannot launch Clinical on the CarPlay display.
- Verify the App Group SQLite database and WAL sidecars use `.completeUntilFirstUserAuthentication`, allowing access after the first device unlock while retaining encrypted storage. [Apple file-protection documentation](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication).

### Hands-free Siri interfaces

Add background-capable App Intents and App Shortcuts:

- `ViewScheduleIntent`: defaults to today, reads at most five appointments aloud, and reports the remaining count.
- `ScheduleAppointmentIntent`: requires patient, date, time, and duration; reads the complete proposed booking back and requires confirmation before writing.
- `RescheduleAppointmentIntent`: requires an existing appointment and new date/time; preserves the current duration unless explicitly changed; confirms old and new times before writing.
- `CancelAppointmentIntent`: requires a future scheduled appointment and explicit confirmation before updating its status.
- Add `PatientIntentEntity` and `AppointmentIntentEntity` with database-backed entity queries. Resolve duplicate patients with first name, last initial, and phone suffix; resolve duplicate appointments with date and time.
- Keep responses voice-complete and avoid snippet-only information because custom visual responses may not appear through CarPlay. App Intents explicitly support voice-only contexts. [Apple App Intents guidance](https://developer.apple.com/documentation/appintents/acceleratingappinteractionswithappintents/).

### Calling limitation

Do not promise a Clinical-specific hands-free cellular-call intent in v1:

- `INStartCallIntent` represents calls placed using the developer’s own calling service and is intended for VoIP/CallKit apps. [Apple `INStartCallIntent` documentation](https://developer.apple.com/documentation/intents/instartcallintent).
- `OpenURLIntent` is restricted to universal links, so it is not a dependable `tel:` handoff mechanism from a background Clinical intent. [Apple `OpenURLIntent` documentation](https://developer.apple.com/documentation/appintents/openurlintent).
- Ordinary Siri calling remains available when the patient is present in system Contacts.
- If Apple later grants a CarPlay entitlement, appointment selection can push a `CPContactTemplate`; its call button can open the patient’s `tel:` URL directly on CarPlay.

### Entitlement-gated follow-up

- The account owner may submit a CarPlay entitlement request describing the schedule-and-call use case, but no production CarPlay UI should be written while approval is unknown.
- If granted, isolate all UIKit/template code under a `carplay` feature folder inside the app target.
- Use a shallow flow: today/upcoming `CPListTemplate` → appointment `CPContactTemplate` → call button.
- Refresh on scene connection, foregrounding, and committed database changes; do not poll.
- Do not create another database, persistence model, SwiftUI surface, app target, or extension.

## Test Plan

- Unit-test appointment commands for successful writes, invalid clinic hours, permitted overlaps/break crossings, stale status, missing records, and concurrent changes.
- Test entity queries for unique names, duplicate names, missing phone numbers, cancelled appointments, and multiple appointments for one patient.
- Test that cancel and reschedule perform no mutation when confirmation is declined.
- Test spoken schedule limits, overflow wording, privacy formatting, and empty schedules.
- Test the compact widget with zero, one, two, and many appointments spanning multiple dates.
- Use App Intents Testing where supported, plus one Shortcuts/Siri smoke pass on an unlocked and subsequently locked iPhone.
- Validate the widget with CarPlay Simulator; no physical-car testing is required for v1.
- If a dedicated CarPlay UI is eventually approved, test 12-item list limits, template-depth limits, touch and rotary navigation, dark/light modes, disconnect/reconnect, and call handoff in CarPlay Simulator.

## Assumptions and Concerns

- Defaults chosen because no preference response was supplied: widget plus Siri, voice-complete appointment changes, and first-name-plus-last-initial privacy.
- Only future, scheduled appointments are eligible for Siri reschedule/cancel resolution.
- Booking requires an explicit duration; rescheduling preserves the existing duration by default.
- No third-party dependencies or schema migration are needed.
- Existing implemented specifications under `docs/specs/` remain untouched; update `docs/widgets.md`, `docs/appointment-booking.md`, and add a short `docs/carplay.md` architecture note.
- The remaining unmet v1 use case is calling a Clinical-only patient who is absent from Contacts. Solving that reliably requires an approved CarPlay UI or materially expanding Clinical into a qualifying communication app, which is not a low-effort lift.
