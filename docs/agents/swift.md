# Swift instructions

For UI work, also read [SwiftUI instructions](swiftui.md).

## Platform and state

- Target iOS 26.0+ and Swift 6.2+. Use strict concurrency and async/await APIs.
- Mark every `@Observable` class `@MainActor`; flag missing annotations. Use these
  classes for shared state. Own them with `@State`; pass them with `@Bindable`
  or `@Environment`.
- Avoid legacy observation (`ObservableObject`, `@Published`, `@StateObject`,
  `@ObservedObject`, `@EnvironmentObject`) except in unavoidable integrations.

## Concurrency

- The app defaults to `MainActor` isolation, including static members and protocol
  conformances. Check isolation before use in `@Sendable` closures or nonisolated
  accessors. Use `nonisolated` for immutable `Sendable` constants and conformances
  that need no actor protection, or capture a `Sendable` local value.
- Use Swift concurrency, not Grand Central Dispatch.
- Use `@Dependency` for registered ambient values such as `Calendar` and `Locale`.
  Use `withDependencies` in tests; do not add test-only parameters.

## APIs and style

- Prefer Swift-native methods, modern Foundation APIs, and static member lookup.
- Use `FormatStyle` for formatting and parse strategies for parsing. Do not use
  C-style number formatting or legacy `Formatter` subclasses.
- Use `localizedStandardContains()` for user-input filtering.
- Avoid force unwraps and force `try` except for unrecoverable failures.
- Reuse domain date/time APIs before adding helpers or manual component arithmetic.
- Group overloads together so their differences are easy to compare.
- Mark unfinished work with `// TODO:`.
