# Appointment Booking Architecture

This document captures the deliberate constraints an agent is likely to break when changing appointment booking.

## Invariants

- Overlapping appointments are valid. The clinic can have multiple doctors attending different patients at the same time, so an existing appointment does not make that interval unavailable.
- Booking during or across the clinic break is valid. The break is a scheduling preference, not unavailable time.
- Automatic time prefilling should prefer an empty interval within the regular working segments because the clinic usually has a single doctor.
- Existing appointments must not restrict manual time selection or saving. Multiple doctors may be available even when the selected interval is occupied.

## Do Not Reintroduce

- Do not turn the prefill preference for empty intervals into a hard availability rule. Visiting doctors make overlapping bookings valid even though they are not the default preference.
- Do not reject a booking because it starts during or extends across the clinic break. Exceptional scheduling must remain possible even though automatic prefilling avoids the break.
