# Roadmap
[Original doc with lots of requirements](https://docs.google.com/document/d/1dWiT6XEOwU3o48DvTp2mEwCcKFEvL732_ve6VYm7DuI/edit?tab=t.0)

## M1: Replace Shortcuts + Calendar setup
- [x] Schedule of appointments
  - [x] Handle appointment overlap (e.g., 2 doctors or incorrect appt duration)
  - [x] Swipe to navigate day-wise
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
  - [ ] Handle (or disallow) missing phone number
- [x] New appointment
  - [x] Show preview in schedule for maximum context
  - [x] Date selection synchronize with schedule
  - [x] Pre-fill next available slot
    - [x] Pre-fill only future times, if date is today
  - [x] Quick-create new patient from new appointment page
- [x] View appointment
  - [x] Jump to patient
  - [ ] For scheduled appointments: Mark as done -> record payment + due, schedule next appt, add “follow-up” tag,  clinical notes in future, implant records, lots of actions…
  - [x] Cancel appointment - confirm cancellation and then hide it from view
- [x] Edit appointment
- [x] Send SMS + WhatsApp Biz message + auto-copy to clipboard
  - [x] Allow editing of message
  - [x] Allow changing contact/number when sending msg
    - [x] Also update Patient record automatically
  - [x] Disable “Send” button if valid phone number is not present
  - [x] Also send location if first appt
  - [x] Add honorific in message greeting
  - [ ] Make sure SMS is sent from Bitehaus number, not personal
- [x] Widget
- [ ] Shortcut to create appointment
- [ ] End of day reminders (maybe location-fenced?) to mark all appointments complete/cancelled, record payments (or indicate "no payment"), etc
  - [ ] Indicators/flags on appointment cards to indicate whether they're processed or not
- [x] Calendar sync for CarPlay + my visibility - but remove Calendar widget from home screen to ensure app adoption
- [ ] Block off time ranges (e.g., travelling, holiday, etc) OR sync to Calendar
- [ ] Add local + cloud logging for release builds (see Logger example in Database.swift)
- [ ] Patient data backups? This system will be a critical dependency for the clinic!
- [ ] Basic dark mode support - check if Monu’s phone has it enabled - contrast is terrible
- [ ] Change the `Bitehaus Debug` target calendar to `Bitehaus` before release
- [ ] Universal search - next to tab bar - search for patients, appointments, payments, search by phone number - entrypoint for several other features
  - [ ] Share recent call / contact to create Patient
  - [ ] Share recent call / contact to open patient details (or show search results if multiple, e.g., family members) associated with that phone number

Refactors:
- [x] Remove TimelineSegment; use TimelineScale for universal placement
- [x] Extract reusable "auto-height" sheet component from AppointmentBooking sheet

Bugs:
- [x] Remove timeline sheet clearance for details sheet - anyway it's modal now!
- [ ] Colors: https://developer.apple.com/design/human-interface-guidelines/color
- [x] Make it impossible to dismiss sheets with unsaved forms (or ask for discard confirmation)
- [ ] Fitted sheet still resizes upon scroll, in patient edit sheet. Other sheets are fine (but they also don't have scrollable contents at the moment, I think, not sure).
- [x] UX invariant: Never show appointment details for date X on the schedule for date Y, to prevent user confusion.
- [x] Simplify Router behaviour - newly-triggered actions are always more critical/time-sensitive compared to whatever was on-screen - interrupting is better than queueing the request
- [ ] Appointment cards in patient details should have a chevron

Observations from in-hand testing:
- [ ] Would be nice to be able to click directly on the schedule and drag to adjust start time, in 5 or 15min increments
  - [ ] Then organize Timeline into clearly-defined Z-stack layers for future extensibility - they are already separate, just organize them better

Nice to haves:
- [x] Toolbar for Complete/Cancel/Call/WhatsApp buttons
- [x] Action Sheets for Complete/Cancel/Discard prompts
- [ ] Quick-add patient button in appointment booking isn't intuitive - should be shown as a search result
- [ ] First non-cancelled appointment should default to 15 min
- [ ] Warning in appointment booking for time in past
- [ ] Fun animated greetings with draw + gradient symbol animations
- [ ] Remove striped pattern from break
- [ ] Animations in empty spaces - resting cat or plant waving in the breeze
- [ ] Variety of pastel or illustrated patient avatars
- [ ] Style hour and now markers like iOS Cal app
- [ ] Reduce visual weight of break, remove 8-9pm and possibly 9-9:30, 4-4:30 (anyway it's possible to schedule in breaks now)
- [x] Display appointments scheduled in break too
- [ ] Add “today”, “yesterday”, “tomorrow” + day in header - or just subtly grey out past dates?
- [ ] Appointment booking: Order patients by most recent appt + recently created first (most common usecase: scheduling a follow-up OR appt for new patient)
- [ ] Quick-tag patients for follow-up, or interested in implants/etc from appointment view
- [ ] Offer phone number selection if picked contact has multiple numbers
- [ ] Jump to specific date?
- [ ] Share phone number (without saving) to app, it will create contact (if shared contact doesn't have a name)
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

High-level structure suggested by ChatGPT: https://chatgpt.com/share/6a5fb3c9-f710-83e8-a54d-d1d5a4580a77

> Keep the imported bank event separate from the business record:
> A bank transaction is evidence that money moved; a Clinical payment explains why it moved

```
struct BankTransaction {
    var id: UUID
    var provider: BankDataProvider
    var externalID: String?
    var bankReference: String?
    var postedAt: Date
    var amount: Decimal
    var direction: Direction
    var narration: String
    var status: Status
    var reconciliationStatus: ReconciliationStatus
    var rawPayloadHash: String
}

struct Payment {
    var id: UUID
    var patientID: Patient.ID?
    var appointmentID: Appointment.ID?
    var amount: Decimal
    var method: PaymentMethod
    var bankTransactionID: BankTransaction.ID?
}
```

## M2.1: iPad optimized
- [ ] Clinic dashboard - appointments, patient records, and payments

## M3: Reduce dependency on paper forms in clinic
- [ ] Add "Notes" in appointment view (inspiration: Bear app on iPad/iPhone)
- [ ] View all Notes on appointment/patient detail pages
- [ ] Scan OPD form with camera, including notes
  - [ ] Use on-device Gemma/edge models? https://youtu.be/-TiET_K-E_g
- [ ] iPad app to view and edit patient records/notes in larger size

## M3.1: Implant tracking
- [ ] Bulk scan implant barcodes for long-term warranty - then allow noting position of each one in patient's mouth

## M4: Eliminate paper forms in clinic
- [ ] [TBD] Patient check-in experience

# Moonshots for later
- Use Swift-Wasm to port to web: https://swift.org/blog/bringing-goodnotes-to-web-with-swift/
