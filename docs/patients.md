# Patients

A patient can have a phone number without a known name. The unknown-patient label
is a display fallback, not a stored name. Contact import must not replace an
existing name or turn an unknown-caller bookkeeping label into a patient identity.

Phone numbers without a country code are Indian numbers. Store normalized numbers
and apply readable grouping for display so contact matching does not depend on
punctuation.

Name search matches word prefixes in any order. A short query such as `an` should
find `Anjali Desai` and `Mary Ann`, but not `Rani Dutta`. Contact-driven search uses
all of the contact's normalized phone numbers because one contact can have several
patient records under different numbers.

Appointment history and upcoming visits are live read models, not patient fields.
Appointment changes must update them without a patient edit. See
[persistence](persistence.md) for read-model ownership and cancellation policy.
