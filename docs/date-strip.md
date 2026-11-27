# Date strip

Pages follow calendar weeks in the [clinic calendar](architecture.md#clinic-date-and-locale).

The schedule owns the selected day. The strip follows other navigation across
week boundaries; scrolling must not create a separate selection.

When day indicators are enabled in Settings, each date shows committed
scheduled and completed appointments split into morning and evening shifts—
ignoring cancelled appointments, unavailable time, drafts, and break hours
(1:00–4:00 PM). Keep the previous, current, and next calendar weeks loaded so
week swipes do not flash empty indicators.
