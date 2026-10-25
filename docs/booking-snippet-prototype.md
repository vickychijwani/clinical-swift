# Booking snippet prototype

This experiment is available in Debug builds. It uses iOS 26 App Intents APIs.
The deployment target does not need to change. The system flow was checked on
the iOS 27 simulator.

## Try it

- In Schedule, tap the sparkle button to open the booking playground.
- Choose a patient. Name search uses the same word-prefix matching as app booking.
- Change the day, start time, or duration. The open-time buttons use the existing
  appointment availability rules. Manual overlaps and bookings across the break
  remain valid.
- Scroll to see all appointments for that day, including the new draft.
- Tap Book demo appointment to show the result. Book another includes earlier
  demo bookings when it finds open times.

For the system UI, use the Shortcuts link in the playground. Run **Try Snippet
Booking** under Clinical. The system asks for a patient, shows the interactive
snippet, and supplies Cancel and Book buttons. In a custom shortcut, set Patient
to Ask Each Time if you want a choice on each run. The `EntityStringQuery` also
supports name search when the system shows a searchable entity picker. The
system controls that picker; the snippet does not contain an editable text field.
Choose the patient before the system confirmation. A second parameter prompt
inside that confirmation dismissed it in the simulator, so patient changes are
available only in the playground. Cancel and run the shortcut again to select
another patient in the system flow.

The system snippet host scrolls the full content and keeps Book available.
The snippet does not need its own nested scroll view. Button actions change the
shared draft. The system then reruns the snippet intent to render a value snapshot.
Rendering must not create a session or book an appointment.

## Data limits

Patients and appointments come from the local clinic database. Reads occur when
patient selection opens and when the selected day changes. This prototype does
not observe changes made elsewhere while the same day remains open. The schedule
shows appointments; unavailable-time blocks are outside this experiment.

Demo bookings and drafts stay in memory. Book never calls the normal persistence
save method. It adds no appointment record, Calendar event, widget update, or
backup change. Closing the app process clears the experiment. Repeated confirmation
of one session returns its existing demo booking.

Production storage, session cleanup, new-patient creation, and recovery from
interruption are deferred. Keep the existing Book Appointment shortcut and normal
booking flow separate while the interaction is under review.

Apple references: [Interactive snippets](https://developer.apple.com/documentation/appintents/displaying-static-and-interactive-snippets),
[Entity string queries](https://developer.apple.com/documentation/appintents/entitystringquery).
