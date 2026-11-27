# Swift and SwiftUI

## Language and concurrency

- Use strict concurrency and `async`/`await` (Swift 6.2+); do not use Grand Central Dispatch.
- Mark every `@Observable` class `@MainActor` and flag missing annotations. Use `@Observable`
  for shared state: own with `@State`, pass with `@Bindable` or `@Environment`. Avoid legacy
  observation (`ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`,
  `@EnvironmentObject`) unless required by an integration.
- The app defaults to `MainActor` isolation, including static members and protocol
  conformances. Check isolation before use in `@Sendable` closures or nonisolated accessors.
  Use `nonisolated` for immutable `Sendable` constants and conformances that need no actor
  protection, or capture a `Sendable` local value.
- Use `@Dependency` for registered ambient values such as `Calendar` and `Locale`. See
  [testing](testing.md) for overriding dependencies in tests.

## APIs and style

- Prefer Swift-native methods, modern Foundation APIs, and static member lookup.
- Use `FormatStyle` for formatting and parse strategies for parsing; do not use C-style
  number formatting or legacy `Formatter` subclasses.
- Use `localizedStandardContains()` for user-input filtering.
- Avoid force unwraps and force `try` except for unrecoverable failures.
- Reuse domain date/time APIs before adding helpers or manual component arithmetic.
- Group overloads together so their differences are easy to compare.
- Mark unfinished work with `// TODO:`.

## SwiftUI

### Structure and state

- Avoid UIKit unless requested. Keep view logic testable outside views.
- Extract subviews into `View` structs, not computed properties. Avoid `AnyView` unless
  required.
- Keep each visual variant's values in one configuration instead of separate switches per
  metric.

### APIs and layout

- Use `foregroundStyle()`, `clipShape(.rect(cornerRadius:))`, and the `Tab` API.
- Use zero- or two-parameter `onChange()`, never the one-parameter form.
- Use `NavigationStack` and `navigationDestination(for:)`.
- Use `Task.sleep(for:)`. Prefer `ImageRenderer` for view rendering.
- Use `bold()` for bold text; use `fontWeight()` only with a specific reason.
- Prefer `containerRelativeFrame()` or `visualEffect()` over `GeometryReader`. Never size
  content with `UIScreen.main.bounds`.
- Pass enumerated sequences directly to `ForEach`; do not wrap them in `Array`.
- Use `.scrollIndicators(.hidden)` and current scrolling APIs (`ScrollPosition`,
  `defaultScrollAnchor`), not `ScrollViewReader`.
- Avoid hard-coded padding, stack spacing, and UIKit colors unless requested.

### Interaction

- Use `Button` unless a gesture needs the tap location or count. Give image buttons text
  labels.
- For plain composite button labels, set the frame before `contentShape()` so transparent
  areas respond to taps. Backgrounds and clipping do not ensure this.
- Use `confirmationDialog` for choices; reserve alerts for errors and information.
- Use `AsyncButton` for immediate async work and `ConfirmingAsyncButton` for confirmed async
  work. Shared operations need model-owned progress and errors.
- Use `ConfirmingTray.swift` for explicit dismissal of unsaved forms. Disable swipe and
  outside-tap dismissal while dirty or saving. Child steps own their dismissal.
