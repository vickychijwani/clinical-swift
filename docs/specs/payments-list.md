---
status: implemented
---

# Payments List

## Purpose

Add a list of money received and money paid out to the Payments tab in
[PR #20](https://github.com/vickychijwani/clinical-swift/pull/20). Use the supplied
design as a visual reference. Use native SwiftUI controls and the app's existing
screen style; exact spacing, fonts, and colors from the image are not required.

## Scope

- Include receipts and expenses. Exclude charges and adjustments.
- Show the complete history, with lazy row construction and live data updates.
  Do not add a date limit or pagination.
- Rows are for display only. Do not add row navigation, swipe actions, an add
  button, entry forms, search, filters, or reports in this work item.
- Show the newest entries first.
- Keep `entryDate` as a date-only value. Omit payment time from every row.
  Group dates using the Gregorian calendar in IST (`Asia/Kolkata`), regardless
  of device settings.
- For an expense or a receipt without a patient, use the first available title:
  the nonblank note, a readable category name, then the exact string `Unknown`.
  Do not add a separate supplier or payer field.
- Show separate signed receipt and expense totals in each day header. Omit a
  side that has no entries. Do not show a net total in place of these totals.
- Show only Cash, UPI, and Card as payment methods. Omit both an unknown method
  and `Other`. Do not show a placeholder, assume Cash, or leave an unused
  separator. Keep the stored method unchanged.
- Omit the separate category labels shown at the right of the reference, such
  as `Patient` and `Supplier`.
- Omit treatment and item descriptions, such as `Composite filling` and
  `Routine cleaning`. Do not derive these from appointment charges.

## Reference Layout

- Keep the existing Payments tab and navigation title.
- Group rows by clinic calendar day. Place the newest day first.
- Use a native SwiftUI `List` with one `Section` per clinic day and
  `.insetGrouped` style, following
  [PatientList.swift](../../clinical-swift/patients/views/PatientList.swift).
  Use native section groups and separators, with the same row insets and
  separator alignment as the Patients list. Keep the shared canvas visible
  behind the list. Each section header contains its date and daily totals.
- Each row has a direction symbol at the leading edge, a main title in the
  middle, and a signed rupee amount at the trailing edge. Put Cash, UPI, or Card
  below the title when present. Otherwise omit the secondary line entirely.
- Use SF Symbols for incoming and outgoing arrows. Match the circular badge
  size and proportions of
  [PatientAvatar.swift](../../clinical-swift/patients/views/PatientAvatar.swift).
  For receipts, use the same `AppColor.success` green as patient avatars:
  full-opacity foreground over a background at 16% opacity by default.
  For expenses, use SwiftUI's native orange through `AppColor.warning`, with
  the same full-opacity foreground and 16%-opacity background treatment.
  The sign and arrow must also identify the direction.
- Keep text and amounts legible in light and dark appearance. Let SwiftUI set
  normal row metrics and spacing.
- Define all app-owned payment colors in
  [AppPalette.swift](../../ClinicalShared/AppPalette.swift), using `AppColor`
  roles. Reuse shared roles for canvas, surfaces, and text. Use the receipt and
  expense base colors for their amounts, daily totals, and arrows. Define their
  tinted backgrounds in the palette, derived from the same base colors, so
  Color Lab changes also update these tints. Keep color values and derived
  tints out of payment views.
- Make these roles controllable through the existing Color Lab. Color changes
  must apply at once while the Payments tab is visible. Preserve native system
  materials and control effects.

## Model Boundaries

The model stores `entryDate` at the start of the clinic day. This work keeps
that rule. Do not add time storage, infer payment time from `createdDate`, or
display midnight as a payment time.

The current model has no separate supplier or payer name. Patient receipts can
use the linked patient's display name. Expenses and other receipts have a
category and an optional note; the note can contain a name or other context.
The available payment methods are Cash, UPI, Card, and Other. Bank is not a
separate value in the current model; do not add it for this list.

## Ordering and Live Data

- Keep the list live with observed SQLite reads. Entry changes and patient name
  changes must update the list without a manual refresh.
- Sort by `entryDate` descending, then `createdDate` descending, then entry ID
  descending. Within a clinic day this puts the most recently recorded entry
  first. Recording order does not establish the actual order of payments.

## Dates, Titles, and Amounts

- Show `Today` and `Yesterday` for those clinic days. Use dates such as
  `Fri, 17 Apr` for other days in the current year, and include the year for
  earlier years, for example `Thu, 17 Apr 2025`. Recompute relative labels at
  clinic midnight and on return to the app.
- Use the patient's current display name for a patient receipt, including the
  existing `Unknown Patient` fallback. Do not replace that name with the note.
- Do not repeat a note below the title. The secondary line contains only a
  visible payment method, such as `UPI`, with no separator.
- Show signed whole rupees with Indian digit grouping and no decimal places:
  `+₹3,200`, `−₹4,800`, and `+₹1,00,000`.
- Match daily total signs and colors to their entry kind. When both totals are
  present, show receipts first, then expenses, with a centered dot between them.

## Days Without Payments

- The displayed day range runs from today back through the earliest receipt or
  expense date in the database, inclusive. Do not add sections before that date.
- Include an empty day section for each past clinic day and today within this
  range. Omit Sundays that have no receipts or expenses,
  including when today is Sunday. Show Sundays that have receipts or expenses.
- An empty day section has its normal date header and a simple secondary-text
  row, `No payments`. Show no totals, amount, direction badge, or payment method
  for that section. Keep the native section and row styling.
- Charges and adjustments do not count as payments. A day with only those
  entries follows the empty-day rule.
- Recompute day sections at clinic midnight and on return to the app. Receipt
  and expense changes must also update empty sections and Sunday visibility.
- Existing payment history will be imported before launch. A completely empty
  payment history and deletion of the last payment do not need dedicated tests.

## Data and Verification Constraints

Follow [payment rules](../payments.md) and the
[persistence boundary](../persistence.md). Calculate daily receipt and expense
totals from the same entries shown for that day, using checked integer
arithmetic. A display total must not wrap or silently omit entries on failure.

Use the existing date storage and whole-day report boundaries. This list does
not change ledger ordering, derived coverage, or balance validation.

Use unit tests for inclusion, ordering, grouping, titles, date and amount
formatting, method omission, and daily totals. Check clinic midnight, year
changes, equal dates and recording timestamps, large amounts, and device
settings outside IST. Cover empty weekdays, an empty today, omitted empty
Sundays, Sundays with receipts or expenses, and the earliest-payment boundary.
Verify the native layout manually with long names and notes, large amounts,
both appearance modes, a long history, and empty day sections. Verify that Color
Lab can change payment colors on the Payments tab and reset them to the palette
defaults.

## Acceptance Criteria

- A mix of charges, adjustments, receipts, and expenses produces rows only for
  receipts and expenses, with the newest entries first.
- The list includes the full history. Entries on the same day use descending
  recording date and entry ID as stable tie-breakers.
- No row shows a payment time. Date storage remains unchanged, and date groups
  use clinic days even when the device uses another calendar or time zone.
- Date headers use `Today`, `Yesterday`, and the agreed date formats. Relative
  labels update when the clinic day changes, including after app suspension.
- Within the displayed day range, non-Sundays without receipts or expenses
  show a `No payments` row under their date header, including today. Their
  headers have no receipt or expense totals.
- Day sections extend from today through the earliest receipt or expense date,
  inclusive, with no sections before that date.
- Empty Sundays are omitted, including an empty Sunday that is today. A Sunday
  with any receipt or expense appears with its normal payment rows and totals.
- Patient receipts show the current patient display name or `Unknown Patient`.
- An expense or a receipt without a patient shows its nonblank note, then its
  readable category name, then `Unknown`, in that fallback order.
- Day headers show separate receipt and expense totals. A day with only
  receipts has no expense total, and a day with only expenses has no receipt
  total.
- Cash, UPI, and Card appear below the title. A missing method or `Other` adds
  neither text nor a blank secondary line. No separator appears in that line.
- Row amounts and daily totals use signed whole rupees and Indian grouping,
  including values of one lakh or more.
- Rows have no separate Patient or Supplier category labels and no itemized
  treatment descriptions.
- Rows have no actions. The screen has no add button, search, or filters.
- Entry changes, removals, and patient renames update visible rows and totals
  without a manual refresh. Empty day sections and Sunday visibility update
  with receipt and expense changes.
- The screen uses a native SwiftUI presentation of the reference layout and
  keeps the existing Payments tab and title.
- Day groups use native inset-grouped `List` sections and separators, with
  row insets and separator alignment that match the Patients list. Direction
  badges match the patient avatars' circular style. Default receipt badges
  use the same native green as patient avatars; expense badges use native
  orange. Both have full-opacity symbols over backgrounds at 16% opacity.
- All app-owned payment colors resolve through `AppPalette.swift`. Color Lab
  controls receipt and expense colors, including their tinted backgrounds, and
  changes update visible rows and daily totals at once. Reset restores the
  palette defaults.

## Completion

On implementation, change this specification's status to `implemented`.
Update maintained guides only if a durable decision changes;
do not rewrite the implemented payment-model specification.
