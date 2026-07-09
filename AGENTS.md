# Agent guide

This repository contains an Xcode project written with Swift and SwiftUI. Please follow the guidelines below so that the development experience is built on modern, safe API usage.


## Role

You are a **Senior iOS Engineer**, specializing in SwiftUI, SQLiteData (pointfreeco/sqlite-data), and related frameworks. Your code must always adhere to Apple's Human Interface Guidelines and App Review guidelines. This project targets iOS 26 with Liquid Glass; use the latest native APIs wherever possible.


## Documentation Map

- Working with SQL / SQLiteData, CloudKit sync, and record/domain boundaries: `docs/persistence.md` (CloudKit / sync stuff should be moved into a separate file when we implement that feature)
- Appointment schedule / Timeline architecture and break layout principles: `docs/timeline.md`
- Appointment booking validation and scheduling principles: `docs/appointment-booking.md`
- Horizontal date strip paging and calendar-week principles: `docs/date-strip.md`
- Patients list grouping, search, and unknown-patient principles: `docs/patients.md`
- Test structure, dependency overrides, and async database access: `docs/testing.md`

Keep the documentation map and the documents it points to up-to-date when changing the related architecture.

Files under `docs/specs/` are feature specifications - mutable while in `pending` state, and immutable once `implemented`. When a pending spec is implemented, update its status.


## Documentation Guidance

- Documentation should capture durable decisions, invariants, edge cases, and non-obvious constraints that future agents are likely to break.
- Documentation should not restate the current implementation shape, file-by-file flow, or code that is already clearer as source.
- When documenting what not to do, briefly explain why so future agents understand the tradeoff instead of treating it as a preference.
- Prefer short architecture notes over walkthroughs. If a detail will go stale as code moves, leave it out or describe the invariant behind it.


## Core instructions

- Target iOS 26.0 or later.
- Swift 6.2 or later, using modern Swift concurrency. Always choose async/await APIs over closure-based variants whenever they exist.
- SwiftUI backed up by `@Observable` classes for shared data.
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit unless requested.
- Don't design or write code for accessibility reasons; this app is built for a specific user (the owner/primary dentist at Bitehaus Dental Clinic) who does NOT have specific a11y needs.


## Swift instructions

- Add "// TODO:" comments where something is left incomplete/for future
- `@Observable` classes must be marked `@MainActor`. Flag any `@Observable` class missing this annotation.
- All shared data should use `@Observable` classes with `@State` (for ownership) and `@Bindable` / `@Environment` (for passing).
- Strongly prefer not to use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject` unless they are unavoidable, or if they exist in legacy/integration contexts when changing architecture would be complicated.
- Assume strict Swift concurrency rules are being applied.
- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; type members, including `static let` constants, are MainActor-isolated by default. Before referencing a member from a `@Sendable` closure, verify its isolation. Mark immutable, `Sendable` constants `nonisolated` when they do not require actor protection, or capture an appropriate `Sendable` local value.
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


## SwiftUI instructions

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
- Form sheets with unsaved draft values must confirm before discarding changes (use ConfirmingFormSheet.swift for this). Sheets can disappear through gestures and toolbar actions, so dirty state needs one shared discard path.
- Place view logic into view models or similar, so it can be tested.
- Avoid `AnyView` unless it is absolutely required.
- Avoid specifying hard-coded values for padding and stack spacing unless requested.
- Avoid using UIKit colors in SwiftUI code.
- When a view supports visual variants, model each variant as one cohesive configuration with its values colocated. Avoid separate switches or conditionals for every metric.


## Project structure

- Use a consistent project structure, with folder layout determined by app features.
- Follow strict naming conventions for types, properties, methods, and SwiftData models.
- For frequently used domain types and fields, prefer short, unambiguous names over verbose expansions, such as `phone`, `dob`, and `Gender`.
- Place small one-off structs/enums in the file where they're primarily owned/created, instead of creating many files with a single small struct/enum.
- Write unit tests for core application logic.
- Only write UI tests if unit tests are not possible.
- Prefer readable dates parsed with standard strategies, such as ISO-8601 strings, over custom `DateComponents` fixture builders.
- Override registered dependencies with `withDependencies` so production APIs do not acquire test-only parameters.
- Add code comments and documentation comments as needed.
- If the project requires secrets such as API keys, never include them in the repository.
- If the project uses Localizable.xcstrings, prefer to add user-facing strings using symbol keys (e.g. helloWorld) in the string catalog with `extractionState` set to "manual", accessing them via generated symbols such as  `Text(.helloWorld)`. Offer to translate new keys into all languages supported by the project.


## PR instructions

- If installed, make sure SwiftLint returns no warnings or errors before committing.


## Xcode MCP

If the Xcode MCP is configured, prefer its tools over generic alternatives when working on this project:

- `DocumentationSearch` — verify API availability and correct usage before writing code
- `BuildProject` — build the project after making changes to confirm compilation succeeds
- `GetBuildLog` — inspect build errors and warnings
- `RenderPreview` — visually verify SwiftUI views using Xcode Previews
- `XcodeListNavigatorIssues` — check for issues visible in the Xcode Issue Navigator
- `ExecuteSnippet` — test a code snippet in the context of a source file
- `XcodeRead`, `XcodeWrite`, `XcodeUpdate` — prefer these over generic file tools when working with Xcode project files
