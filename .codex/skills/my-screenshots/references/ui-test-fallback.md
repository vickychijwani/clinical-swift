# UI test fallback

Read this only when simulator control cannot reach a required control or system
screen. The first capture used a temporary XCTest runner for pickers, Contacts,
and SpringBoard. Its old files and container paths are not required for a new run.

Prefer a short temporary capture test for the routes that remain. Put it in the
current UI test target. Use `nonisolated final class …: XCTestCase` and mark test
methods `@MainActor`, as in the existing UI tests. Read the current test scheme
and target settings. Do not change production views to make capture taps work.

- Use `XCUIApplication(bundleIdentifier:)` with the resolved app bundle ID.
  Activate the installed app to preserve the current route and fixture.
- Query current labels or identifiers. Require existence and a unique intended
  match; do not silently choose the first of several matches. Check the visible
  result after each action. Wait for the expected control rather than use a long
  fixed delay.
- Use `XCUIDevice.shared.press(.home)` and
  `XCUIApplication(bundleIdentifier: "com.apple.springboard")` for Home Screen
  and widget-gallery actions. Derive labels and positions from the current tree.
- Use `XCUIScreen.main.screenshot().pngRepresentation` for a full-display PNG.
  An app-only screenshot can omit system UI needed for the reference set.
- Run only the capture test. Save build/test logs in `build/screenshot-capture/`.
  Read the current Makefile test flags, including package cache paths. Do not
  rerun the entire UI test suite for each capture.

If many interactive actions remain, one temporary command runner can reduce
test launches. Use a bounded command loop in the test runner's Documents folder.
Print that folder once at startup, then resolve its path from the current log.
Use atomic command writes, unique request IDs, result acknowledgements, and a
finish command. Return an error for a missing control, invalid action, or timeout.
Save the screenshot and UI tree on disk; return only a short result to chat.
Do not treat a timeout as a successful capture or consume an old result.

Resolve output containers again after each reinstall or test launch. Simulator
container UUIDs can change. Copy only verified captures to `screenshots/`.
Finish the runner and check the test result before removing the temporary source.
Revert only runner-related project edits. Report any remaining temporary changes
or capture states that could not be reached.
