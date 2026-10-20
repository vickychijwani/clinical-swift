# Swift instructions

Read this file before you write, change, review, or plan Swift code. For SwiftUI
work, also read [SwiftUI instructions](swiftui.md).

## Platform and shared data

- Target iOS 26.0 or later.
- Swift 6.2 or later, using modern Swift concurrency. Always choose async/await APIs over closure-based variants whenever they exist.
- SwiftUI backed up by `@Observable` classes for shared data.

## Language and concurrency

- Add "// TODO:" comments where something is left incomplete/for future
- `@Observable` classes must be marked `@MainActor`. Flag any `@Observable` class missing this annotation.
- All shared data should use `@Observable` classes with `@State` (for ownership) and `@Bindable` / `@Environment` (for passing).
- Strongly prefer not to use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject` unless they are unavoidable, or if they exist in legacy/integration contexts when changing architecture would be complicated.
- Assume strict Swift concurrency rules are being applied.
- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; type members, including `static let` constants, and protocol conformances are MainActor-isolated by default. Before referencing a member from a `@Sendable` closure or using a conformance from a nonisolated accessor, verify its isolation. Mark immutable, `Sendable` constants and dependency/protocol conformances `nonisolated` when they do not require actor protection, or capture an appropriate `Sendable` local value.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using `replacing("hello", with: "world")` with strings rather than `replacingOccurrences(of: "hello", with: "world")`.
- Prefer modern Foundation API, for example `URL.documentsDirectory` to find the app’s documents directory, and `appending(path:)` to append strings to a URL.
- Never use C-style number formatting such as `Text(String(format: "%.2f", abs(myNumber)))`; always use `Text(abs(change), format: .number.precision(.fractionLength(2)))` instead.
- Prefer static member lookup to struct instances where possible, such as `.circle` rather than `Circle()`, and `.borderedProminent` rather than `BorderedProminentButtonStyle()`.
- Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. If behavior like this is needed, always use modern Swift concurrency.
- Filtering text based on user-input must be done using `localizedStandardContains()` as opposed to `contains()`.
- Avoid force unwraps and force `try` unless it is unrecoverable.
- Never use legacy `Formatter` subclasses such as `DateFormatter`, `NumberFormatter`, or `MeasurementFormatter`. Always use the modern `FormatStyle` API instead. For example, to format a date, use `myDate.formatted(date: .abbreviated, time: .shortened)`. To parse a date from a string, use `Date(inputString, strategy: .iso8601)`. For numbers, use `myNumber.formatted(.number)` or custom format styles.
- Use `@Dependency` for registered ambient values such as `Calendar` and `Locale`. Override them with `withDependencies` in tests rather than threading them through initializers and methods solely for testability.
- Before adding date/time helpers or manual component arithmetic, search existing domain types and extensions. Prefer semantic APIs such as `TimeOfDay.totalMinutes` and `TimeOfDay.on(date:using:)`.
- Keep overloads grouped together so readers can compare related entry points and avoid missing
  behavior that only differs by parameter shape.

