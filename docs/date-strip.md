# Date strip

Pages follow calendar weeks in the [clinic calendar](architecture.md#clinic-date-and-locale).

The schedule owns the selected day. The strip follows other navigation across
week boundaries; scrolling must not create a separate selection.

Day capacity indicators reflect committed appointments during morning and evening
shifts only, deliberately excluding unavailable time, drafts, and break hours.
