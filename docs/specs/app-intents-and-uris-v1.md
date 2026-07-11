----
status: pending
----

# App Intents & URIs v1

## Use cases served by v1 of this feature

1. Open appointment booking flow directly from a Siri shortcut, homescreen/today widget, hardware Action Button, etc.
2. Share contact to Clinical to open Patient details (or view all patients associated with any of the contact's numbers, if multiple numbers or multiple linked patients to those numbers exist)

The ideal implementation is both:

- App Intent for Siri, Shortcuts, Spotlight, Action button, and related system surfaces.
- `clinical://appointments/book` for widget/deep-link navigation.

They remain thin adapters over one router-owned booking operation, not separate implementations.

## App Intents

Add two Clinical actions:

- “Book Appointment” — opens the general booking flow.
- “Find Patient from Contact” — accepts an `IntentPerson`, examines its primary handle and aliases, and extracts every phone number. iOS 26 exposes contacts and phone handles directly to App Intents.

For contact matching:

1. Normalize every supplied phone through the existing `PhoneNumber.swift`.
2. Remove duplicates.
3. Query patients whose stored phone matches any normalized number.
4. If exactly one distinct patient matches, open their details using the existing external-routing behavior in `Router.swift`.
5. If none match, report “No matching patient.”
6. If multiple patients match, open search results for that phone number.

[Not to be implemented, just here for context] The user of the app would then create a personal Shortcut that:

1. Receives only **Contacts** from the share sheet.
2. Passes **Shortcut Input** into Clinical’s “Find Patient from Contact” action.
3. Is named something like “Open in Clinical.”

Apple confirms that contact cards shared from Contacts are supported Shortcut input, and contact-only shortcuts appear as relevant share-sheet actions: [Shortcut contact input](https://support.apple.com/en-nz/guide/shortcuts/apd7644168e1/ios), [limiting share-sheet input](https://support.apple.com/en-euro/guide/shortcuts/apd8195f96d6/ios).

This avoids a Share Extension. That matters because extensions run separately from their containing app, require shared-container architecture to access data, and aren’t a reliable supported way to launch the main app directly. [Apple’s extension guidance](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html).

## Custom URI for Widget

For a Home Screen or Today View widget, Apple recommends using a `Link` when tapping should open the app, rather than an interactive `Button(intent:)`. Interactive widget buttons are intended to perform work without merely launching the app. [Apple’s WidgetKit guidance](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).

The widget would contain something like:

```swift
Link(destination: URL(string: "clinical://appointments/book")!) {
    Label("Book Appointment", systemImage: "plus")
        .labelStyle(.iconOnly)
}
```

Both entry mechanisms should feed one shared app action:

```text
Siri / Shortcuts → BookAppointmentIntent ─┐
Widget Link       → clinical://…          ├→ Router booking request
In-app button     → direct router call ───┘
```

Then:

- `ContentView.onOpenURL` parses `clinical://appointments/book`.
- The URL handler selects Schedule and creates the parameterless booking request.
- The widget uses the URI through `Link`.
- The App Intent uses iOS 26’s `supportedModes = [.foreground(.immediate)]`, then invokes the same booking request.
- A future home screen inside the app uses a normal SwiftUI `Button` calling the router directly.
