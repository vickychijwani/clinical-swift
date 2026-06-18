# Basics
[Original doc with lots of requirements](https://docs.google.com/document/d/1dWiT6XEOwU3o48DvTp2mEwCcKFEvL732_ve6VYm7DuI/edit?tab=t.0)

## M1: Replace Shortcuts + Calendar setup
- [x] Schedule of appointments
  - [x] Handle appointment overlap (e.g., 2 doctors or incorrect appt duration)
  - [ ] Swipe to navigate day-wise
  - [ ] Jump to date?
  - [ ] Add “today”, “yesterday”, “tomorrow” + day in header
- [x] Patients list
- [x] New patient
  - [ ] Pick contact first - autofill patient name
  - [ ] Or share contact to create Patient
- [ ] View patient
- [ ] Edit patient
- [ ] New appointment
  - [ ] Show schedule above for maximum context
  - [ ] Date selection synchronize with schedule
  - [ ] Pre-fill next available slot 
  - [ ] Show draft appt preview embedded in timeline
  - [ ] Quick-add new patient from new appointment page
  - [ ] Share recent call to open new appointment page for patient associated with that phone number
- [ ] View appointment
- [ ] Edit appointment
- [ ] Delete appointment
- [ ] Send SMS + WhatsApp Biz message + auto-copy to clipboard
  - [ ] Allow editing of message
  - [ ] Allow changing contact/number when sending msg (sometimes number changes temporarily or permanently - shouldn’t require Patient record update)
  - [ ] Don't put patient's name OR add honorific before name
  - [ ] Also send location if first appt
  - [ ] Make sure SMS is sent from Bitehaus number, not personal
- [ ] Widget
- [ ] Shortcut to create appointment
- [ ] Calendar sync for CarPlay + my visibility - but remove Calendar widget from home screen to ensure app adoption
- [ ] Block off time ranges (e.g., travelling, holiday, etc) OR sync to Calendar
- [ ] Add local + cloud logging for release builds (see Logger example in Database.swift)
- [ ] Patient data backups? This system will be a critical dependency for the clinic!

Bugs:
- [x] Make it impossible to dismiss sheets with unsaved forms (or ask for discard confirmation)

Nice to haves:
- [ ] Drag-n-drop to reschedule appointments
- [ ] Appointment booking: Order patients by most recent appt first (most common usecase: scheduling a follow-up)
- [ ] Quick-tag patients for follow-up, or interested in implants/etc from appointment view
- [ ] Offer phone number selection if picked contact has multiple numbers
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
- [ ] Chart of cash flow per month
- [ ] Chart of new and repeat patients per month

Nice to haves:
- [ ] For each outgoing payment, ask "Is this an operating expense or an investment?" (find better words understood by Monu) - useful for calculating net vs op. profit and margin
- [ ] "You have untagged expenses" - tag each expense entity once (e.g., an outgoing payment with entity = "Shruti" could be tagged as "Op Ex" + "Salary")
- [ ] Have a lightweight cards-based UI - predict the likely category of a new expense entity using Apple Foundation Models etc (e.g., on 30/06 we added "Assistants salary" in Bitehaus Finances, instead of names like "Shruti"), and let the user tap a checkmark to accept it, or edit the category and then accept it.
- [ ] Automatically read incoming/outgoing transaction notifications from Gmail? You can even create a simple Google Workspace MCP server [directly with Google Apps Script](https://github.com/tanaikech/MCPApp)! Show a card like "Review detected payments" and let user select which ones should be recorded, edit them in-line, or dismiss
- [ ] Photo(s) of bills for outgoing payments (note: there may be more than 1)
- [ ] Auto-populate outgoing payment from bill photo

## M3: Reduce dependency on paper forms in clinic
- [ ] Add "Notes" in appointment view
- [ ] Scan OPD form with camera, including notes
- [ ] iPad app to view and edit patient records/notes in larger size

## M4: Eliminate paper forms in clinic
- [ ] [TBD] Patient check-in experience

# Moonshots for later
- Use Swift-Wasm to port to web: https://swift.org/blog/bringing-goodnotes-to-web-with-swift/
