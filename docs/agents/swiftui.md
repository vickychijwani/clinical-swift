# SwiftUI instructions

Read this file before you write, change, review, or plan SwiftUI code or app UI.
Also read [Swift instructions](swift.md).

## UI constraints

- Avoid UIKit unless requested.
- Don't design or write code for accessibility reasons; this app is built for a specific user (the owner/primary dentist at Bitehaus Dental Clinic) who does NOT have specific a11y needs.

## Views and interaction

- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use `ObservableObject`; always prefer `@Observable` classes instead.
- Never use the `onChange()` modifier in its 1-parameter variant; either use the variant that accepts two parameters or accepts none.
- Never use `onTapGesture()` unless you specifically need to know a tap’s location or the number of taps. All other usages should use `Button`.
- For plain buttons with composite labels containing `Spacer` or other transparent areas, give the
  label its intended frame and apply `contentShape()` after the frame. Backgrounds and clipping
  define appearance, not a reliable hit-testing boundary.
- Never use `Task.sleep(nanoseconds:)`; always use `Task.sleep(for:)` instead.
- Never use `UIScreen.main.bounds` to read the size of the available space.
- Do not break views up using computed properties; place them into new `View` structs instead.
- Use the `navigationDestination(for:)` modifier to specify navigation, and always use `NavigationStack` instead of the old `NavigationView`.
- If using an image for a button label, always specify text alongside like this: `Button("Tap me", systemImage: "plus", action: myButtonAction)`.
- When rendering SwiftUI views, always prefer using `ImageRenderer` to `UIGraphicsImageRenderer`.
- Don’t apply the `fontWeight()` modifier unless there is good reason. If you want to make some text bold, always use `bold()` instead of `fontWeight(.bold)`.
- Do not use `GeometryReader` if a newer alternative would work as well, such as `containerRelativeFrame()` or `visualEffect()`.
- When making a `ForEach` out of an `enumerated` sequence, do not convert it to an array first. So, prefer `ForEach(x.enumerated(), id: \.element.id)` instead of `ForEach(Array(x.enumerated()), id: \.element.id)`.
- When hiding scroll view indicators, use the `.scrollIndicators(.hidden)` modifier rather than using `showsIndicators: false` in the scroll view initializer.
- Use the newest ScrollView APIs for item scrolling and positioning (e.g. `ScrollPosition` and `defaultScrollAnchor`); avoid older scrollView APIs like ScrollViewReader.
- Use `confirmationDialog` for confirmation prompts everywhere; reserve alerts for errors or informational messages that do not present a choice between actions.
- Use `AsyncButton` when a button tap immediately starts async work. Use `ConfirmingAsyncButton` when a button must show a confirmation dialog before starting async work. Keep shared in-flight state and errors in the owning model when multiple controls or call paths can trigger the same operation.
- Form sheets with unsaved draft values must confirm before discarding changes (use ConfirmingFormSheet.swift for this). Sheets can disappear through gestures and toolbar actions, so dirty state needs one shared discard path.
- Place view logic into view models or similar, so it can be tested.
- Avoid `AnyView` unless it is absolutely required.
- Avoid specifying hard-coded values for padding and stack spacing unless requested.
- Avoid using UIKit colors in SwiftUI code.
- When a view supports visual variants, model each variant as one cohesive configuration with its values colocated. Avoid separate switches or conditionals for every metric.

