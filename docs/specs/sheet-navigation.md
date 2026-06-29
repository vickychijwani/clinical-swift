----
status: complete
----

# Details Sheet Cross-Navigation

## Summary

Introduce a reusable modal details flow that can start with either appointment or patient details
and preserve navigation history as users move between related records. The first use case is
selecting the patient row in appointment details, which pushes patient details within the existing
sheet.

## Invariants

- A single sheet owns a local `NavigationStack` for the complete details flow. Do not present each
  destination as another sheet because these are hierarchical destinations that require standard
  back navigation.
- Model patient and appointment details as routes identified by record ID. The route used to present
  the sheet is its root; destination type does not determine whether a screen is a root.
- The root may be patient details or appointment details. Future links may therefore produce flows
  such as appointment -> patient, patient -> appointment, or deeper combinations of both.
- Preserve the exact navigation history, including repeated routes such as appointment A -> patient
  P -> appointment A. Do not deduplicate routes or jump to an earlier occurrence because Back must
  retrace the path the user followed.
- Keep the modal path scoped to the presented details flow. Opening a related record from within the
  flow must not switch tabs or mutate an app-level tab navigation path.
- The root destination shows a standard xmark that dismisses the sheet. Pushed destinations use the
  back chevron supplied by `NavigationStack`; Back returns to the immediately preceding destination.
- Dragging down dismisses the entire sheet and its local navigation history, regardless of the
  currently displayed destination.
- The flow container owns only presentation and navigation controls. Each destination owns its
  navigation title and contextual toolbar actions so those actions remain correct at any depth.
- Derive contextual actions from the currently loaded record. For example, an appointment
  destination may show `Send Reminder` only while that appointment is scheduled, whether the
  appointment is the root or a pushed destination.
- Prefer trailing placement for contextual actions so they do not compete with the leading xmark or
  back chevron. If several actions are needed, group lower-priority actions in a standard menu.
- Ensure the root xmark is conditional on navigation depth. A container-level xmark that remains
  visible on pushed destinations would conflict with SwiftUI's automatic back chevron and make the
  dismissal scope ambiguous.
- Only the patient row is interactive, not the appointment date and time content. Implement it as a
  `Button` with a disclosure chevron so its behavior and accessibility are clear.
- Before showing patient details, expand the sheet to at least the medium detent so the destination
  is usable. Going back preserves the sheet's current detent.
- Load each destination's current details read model by record ID. In particular, do not manufacture
  a partial `PatientDetails` value with `nextAppointmentDate` set to `nil`; patient details should
  show the same derived metadata regardless of its entry point.
- If a routed record no longer exists, keep the navigation history intact and show an unavailable
  state with Back still functional. Do not silently dismiss the sheet or remove unrelated history.
- Use standard SwiftUI navigation and presentation APIs throughout.

## Routing State

- Reuse the app's `Router` as the coordinator and reuse the existing `Route.patient` and
  `Route.appointment` values for tab navigation, modal navigation, and parsed external links.
- Keep `schedulePath`, `patientsPath`, and any future tab paths exclusively for destinations pushed
  inside those tabs' `NavigationStack`s. Do not store sheet history in a tab path because a tab push
  cannot represent the sheet's presentation boundary, root xmark, detents, or drag dismissal.
- Add a separately scoped optional details presentation to `Router`. The presentation owns a root
  `Route`, a path of subsequently pushed `Route` values, and a stable presentation identity.
- Present the shared details sheet from a common ancestor of all tabs so schedule selections,
  patient selections, widgets, and notifications enter the same flow.
- Internal cross-navigation appends to the active details path and preserves the selected tab.
- An external deep link first selects the appropriate underlying tab and then creates a new details
  presentation whose root is the linked route. Appointment links use the Schedule tab; patient
  links use the Patients tab.
- If an external deep link arrives while a details sheet is already presented, replace the complete
  presentation with a new identity and the linked route as its root. Do not append it to the old
  history; external links are independent entry points and must show an xmark rather than Back.
- Convert widget URLs, notification payloads, and future external entry points into the same `Route`
  representation before updating `Router`. Keep URL and payload parsing out of destination views.
- `Router` is shared UI state and must be `@MainActor` in addition to `@Observable`.

## Initial Scope

- Appointment details -> patient details navigation.
- The reusable flow and route model needed for patient details or appointment details to be a root.
- Consistent root dismissal controls when patient details is opened directly from the Patients tab.
- Router state and entry-point APIs that keep tab paths separate from the details presentation and
  allow a future deep link to replace that presentation with a new root.
- Patient appointment timelines, appointment -> patient -> appointment links, and actions such as
  sending reminders are future features. Widget URL handling and notification registration are also
  future integrations. This work must leave those features compatible with the invariants above; it
  does not implement them.

## Acceptance Criteria

- From the Schedule tab, open an appointment and select its patient row. Patient details appears
  without changing tabs.
- Patient details shows a back chevron. Using it returns to the same appointment details screen.
- Appointment details shows an xmark. Using it dismisses the complete sheet.
- Patient details opened directly from the Patients tab shows an xmark and dismisses its sheet.
- Opening patient details from the short appointment detent expands the sheet to at least medium.
- Patient details displays current patient data and the same derived metadata available when opened
  from the Patients tab.
- The reusable flow can represent either a patient or an appointment as its root and can append
  either route type without changing the selected tab's navigation path.
- Destination-owned toolbar items can coexist with the root xmark or pushed back chevron without
  showing both navigation controls at once.
- Tab navigation paths remain unchanged while users cross-navigate inside a details sheet.
- Routing an external appointment or patient entry replaces any active details history, selects the
  appropriate underlying tab, and displays the linked record as a new root with an xmark.
