# SwiftUI instructions

Also read [Swift instructions](swift.md).

## Scope and state

- Avoid UIKit unless requested. Accessibility-specific work is out of scope
  unless requested.
- Use `@Observable`, never `ObservableObject`. Keep view logic testable outside views.
- Extract subviews into `View` structs, not computed properties. Avoid `AnyView`
  unless required.
- Keep each visual variant's values in one configuration, not separate switches
  for each metric.

## APIs and layout

- Use `foregroundStyle()`, `clipShape(.rect(cornerRadius:))`, and the `Tab` API.
- Use zero- or two-parameter `onChange()`, never the one-parameter form.
- Use `NavigationStack` and `navigationDestination(for:)`.
- Use `Task.sleep(for:)`. Prefer `ImageRenderer` for view rendering.
- Use `bold()` for bold text; use `fontWeight()` only with a specific reason.
- Prefer `containerRelativeFrame()` or `visualEffect()` to `GeometryReader`.
  Never size content with `UIScreen.main.bounds`.
- Pass enumerated sequences directly to `ForEach`; do not wrap them in `Array`.
- Use `.scrollIndicators(.hidden)` and current scrolling APIs such as
  `ScrollPosition` and `defaultScrollAnchor`, not `ScrollViewReader`.
- Avoid hard-coded padding and stack spacing unless requested. Avoid UIKit colors.

## Interaction

- Use `Button` unless a gesture needs the tap location or count. Give image buttons
  text labels.
- For plain composite button labels, set the frame before `contentShape()` so
  transparent areas respond to taps. Backgrounds and clipping do not ensure this.
- Use `confirmationDialog` for choices; reserve alerts for errors and information.
- Use `AsyncButton` for immediate async work and `ConfirmingAsyncButton` for
  confirmed async work. Shared operations need model-owned progress and errors.
- Use `ConfirmingTray.swift` for explicit dismissal of unsaved forms. Disable swipe
  and outside-tap dismissal while dirty or saving. Child steps own their dismissal.
