# Roadmap
[Original doc with lots of requirements](https://docs.google.com/document/d/1dWiT6XEOwU3o48DvTp2mEwCcKFEvL732_ve6VYm7DuI/edit?tab=t.0)

## M1: Replace Shortcuts + Calendar setup
- [x] Schedule of appointments
  - [x] Handle appointment overlap (e.g., 2 doctors or incorrect appt duration)
  - [ ] Swipe to navigate day-wise
- [x] Patients list
- [x] New patient
  - [x] Pick contact first - autofill patient name
  - [ ] Show contact card “attached” on patient details
- [x] View patient
  - [x] Timeline of appointments (all - future, present, past)
    - [x] Remember to refresh timeline when navigating back from an appointment's details - date/time could have changed
  - [x] Schedule Appointment button
  - [x] Edit patient
  - [x] Hide optional details like dob/gender to reduce friction with first-appointment creation
- [x] New appointment
  - [x] Show preview in schedule for maximum context
  - [x] Date selection synchronize with schedule
  - [x] Pre-fill next available slot
    - [ ] Consider only future times (e.g., when scheduling a same-day appointment)
  - [ ] Quick-add new patient from new appointment page
- [x] View appointment
  - [x] Jump to patient
  - [ ] For scheduled appointments: Mark as done -> record payment + due, schedule next appt, add “follow-up” tag,  clinical notes in future, implant records, lots of actions…
  - [x] Cancel appointment - confirm cancellation and then hide it from view
- [x] Edit appointment
- [ ] Universal search - next to tab bar - search for patients, appointments, payments, search by phone number - entrypoint for several other features
  - [ ] Share recent call / contact to create Patient
  - [ ] Share recent call / contact to open patient details (or show search results if multiple, e.g., family members) associated with that phone number
- [ ] Send SMS + WhatsApp Biz message + auto-copy to clipboard
  - [ ] Allow editing of message
  - [ ] Allow changing contact/number when sending msg (sometimes number changes temporarily or permanently - shouldn’t require Patient record update)
  - [ ] Don't put patient's name OR add honorific before name
  - [ ] Also send location if first appt
  - [ ] Make sure SMS is sent from Bitehaus number, not personal
- [ ] Widget
- [ ] Shortcut to create appointment
- [ ] End of day reminders (maybe location-fenced?) to mark all appointments complete/cancelled, record payments (or indicate "no payment"), etc
  - [ ] Indicators/flags on appointment cards to indicate whether they're processed or not
- [ ] Calendar sync for CarPlay + my visibility - but remove Calendar widget from home screen to ensure app adoption
- [ ] Block off time ranges (e.g., travelling, holiday, etc) OR sync to Calendar
- [ ] Add local + cloud logging for release builds (see Logger example in Database.swift)
- [ ] Patient data backups? This system will be a critical dependency for the clinic!
- [ ] Basic dark mode support - check if Monu’s phone has it enabled - contrast is terrible

Refactors:
- [x] Remove TimelineSegment; use TimelineScale for universal placement
- [x] Extract reusable "auto-height" sheet component from AppointmentBooking sheet

Bugs:
- [x] Make it impossible to dismiss sheets with unsaved forms (or ask for discard confirmation)
- [ ] Fitted sheet still resizes upon scroll, in patient edit sheet. Other sheets are fine (but they also don't have scrollable contents at the moment, I think, not sure).
- [ ] When switching to a different date, selected appointment sheet should be dismissed (record a UX invariant: never show appointment details for date X on the schedule for date Y, to prevent user confusion). However, if navigation within sheet is used to go from appointment on date X -> patient -> appointment on date Y, then instead jump to date Y in schedule but keep the date X appointment in navigation history - and switch back to the date X schedule when navigating back to that appointment. In other words, bind the date strip to selected appointment at all times - and dismiss the sheet if the date is changed by selecting on the date strip directly.
- [x] Cancel button is too prominent; make Complete take more space, and Cancel/Reschedule can be smaller-size controls
- [x] Appointment details sheet background is white when opened from patient details
- [ ] Appointment cards in patient details should have a chevron

Observations from in-hand testing:
- [ ] Would be nice to be able to click directly on the schedule and drag to adjust start time, in 5 or 15min increments

Nice to haves:
- [x] Appointment summary card - Instead of cal icon use non-cal icons for scheduled, completed, cancelled, etc
- [x] Toolbar for Complete/Cancel/Call/WhatsApp buttons
- [ ] Action Sheets for Complete/Cancel/Discard prompts
- [ ] Fun animated welcome text with draw + gradient symbol animations
- [ ] Direct interactions with Timeline for appointment booking/reschedule
  - [ ] First organize Timeline into clearly-defined Z-stack layers - they are already separate, just organize them better
- [ ] Variety of pastel or illustrated patient avatars
- [ ] Remove year from header, make it less prominent (see iOS Calendar app)
- [ ] Style hour and now markers like iOS Cal app
- [x] Display appointments scheduled in break too
- [ ] Drag-n-drop to reschedule appointments
- [ ] Add “today”, “yesterday”, “tomorrow” + day in header - or just subtly grey out past dates
- [ ] Appointment booking: Order patients by most recent appt first (most common usecase: scheduling a follow-up)
- [ ] Quick-tag patients for follow-up, or interested in implants/etc from appointment view
- [ ] Offer phone number selection if picked contact has multiple numbers
- [ ] Jump to date?
- [ ] Pre-fill appt time with next available slot (consider clinic opening times + booked slots + unbookable slots)
- [ ] Share phone number (without saving) to app, it will create contact (if shared contact doesn't have a name)
- [ ] Add "Schedule appointment" button on patient details page - prefill patient when tapped
- [ ] Merge patient A with patient B - when multiple patients are created accidentally (or due to a bug)
- [ ] When contact with name + number is shared - open patient view page if already exists (name + number, fallback to just number) for quick appt scheduling, OR open patient edit page to create new pt
  - [ ] Offer selection if multiple patients have same number
- [ ] GMB link at top right of home page, button to msg Rajesh for pickup
- [ ] Occasional reminders / manual button to share Google review link + text with patient on WA Biz

## M2: Replace Bitehaus Finances sheet
- [ ] History of payments - new tab
- [ ] Record incoming from appt view
- [ ] Record incoming/outgoing from payments tab
- [ ] Record ad-hoc incoming (radiographic fee, Dr. Chaitra, etc)
- [ ] Chart of cash flow per month
- [ ] Chart of new and repeat patients per month

Nice to haves:
- [ ] For each outgoing payment, ask "Is this an operating expense or an investment?" (find better words understood by Monu) - useful for calculating net vs op. profit and margin
- [ ] "You have untagged expenses" - tag each expense entity once (e.g., an outgoing payment with entity = "Shruti" could be tagged as "Op Ex" + "Salary")
- [ ] Have a lightweight cards-based UI - predict the likely category of a new expense entity using Apple Foundation Models etc (e.g., on 30/06 we added "Assistants salary" in Bitehaus Finances, instead of names like "Shruti"), and let the user tap a checkmark to accept it, or edit the category and then accept it.
- [ ] Automatically read incoming/outgoing transaction notifications from Gmail? You can even create a simple Google Workspace MCP server [directly with Google Apps Script](https://github.com/tanaikech/MCPApp)! Show a card like "Review detected payments" and let user select which ones should be recorded, edit them in-line, or dismiss
- [ ] Photo(s) of bills for outgoing payments (note: there may be more than 1)
- [ ] Auto-populate outgoing payment from bill photo

## M2.1: iPad optimized
- [ ] Clinic dashboard - appointments, patient records, and payments

## M3: Reduce dependency on paper forms in clinic
- [ ] Add "Notes" in appointment view
- [ ] View all Notes on appointment/patient detail pages
- [ ] Scan OPD form with camera, including notes
- [ ] iPad app to view and edit patient records/notes in larger size

## M3.1: Implant tracking
- [ ] Bulk scan implant barcodes for long-term warranty - then allow noting position of each one in patient's mouth

## M4: Eliminate paper forms in clinic
- [ ] [TBD] Patient check-in experience

# Moonshots for later
- Use Swift-Wasm to port to web: https://swift.org/blog/bringing-goodnotes-to-web-with-swift/
