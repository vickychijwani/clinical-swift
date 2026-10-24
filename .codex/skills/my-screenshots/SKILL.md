---
name: my-screenshots
description: Capture Clinical app screens, distinct control states, and live Home Screen widgets for design work. Use for a full screenshot set or an update to an existing set in screenshots/.
---

# App screenshot capture

Save full-screen simulator PNGs in `screenshots/`. Cover the requested screens and distinct visible control states with as few images as practical. Include live Home Screen widgets for a full capture. These screenshots will be used to re-create their designs in Figma for further design explorations.

For a full run, check every reachable screen even when its source did not change. For an update, reuse verified images when their relevant source and setup still match; mark reused images with their original capture date.

Update the capture log in `screenshots/README.md` when you're done.

## Find the current scope

1. Read repository instructions and `screenshots/README.md`. Treat its image
   list as a prior capture record, not a fixed screen list. Do not load the old
   capture chat unless a specific missing detail requires it.
2. Check Git status, the current Makefile, source folders, and available simulator
   tools. If the README records a source revision, use its diff to find changes.
   Always check current navigation roots and widget declarations as well.
3. Use `rg --files` to find app entry points, views, routing, shared controls,
   widgets, sample data, and UI test support. Search the current source folders:

   ```sh
   rg -n 'Tab\(|NavigationStack|navigationDestination|\.sheet|\.popover|confirmationDialog|\.alert|Menu\(|Picker\(|Button\(|AsyncButton|TextField\(|TextEditor\(|Toggle\(|DisclosureGroup|searchable|disabled\(|supportedFamilies|WidgetConfiguration|onOpenURL' <source-folders> -g '*.swift'
   ```

   Follow custom wrappers, route cases, and relevant view-model conditions. Read
   only the source ranges needed to identify visible states and how to reach them.
   Search results are leads, not a complete inventory. Check the running UI for
   controls that the source search missed.
4. Write a small capture plan in `build/screenshot-capture/coverage.md` with:
   `screen/control | distinct state | route/data needed | PNG or limit`.
   Include new screens and changed controls. Remove obsolete targets. For a full
   run, check every reachable screen even when its source did not change. For an
   update, reuse verified images only when their relevant source and setup still
   match; mark reused images with their original capture date.

## Check and deliver

Run the Swift helper with the Xcode toolchain:

```sh
xcrun swift -O -Xfrontend -parse-as-library .codex/skills/my-screenshots/scripts/check_images.swift screenshots \
  --sheets build/screenshot-capture/contact-sheets \
  --report build/screenshot-capture/images.json
```

The helper checks PNG integrity, dimensions, and exact pixel duplicates. It does
not prove screen coverage. Inspect every contact sheet, then open full-size images
only where details are unclear. Check for wrong screens, clipped controls,
unintended keyboards, permission prompts, stale widgets, and transitional frames.
Resolve duplicate images or explain why both files are needed.

Compare the checked images with the capture plan. Each target must have a PNG or
a stated limit. Update `screenshots/README.md` with run metadata, a small starting
set chosen from current coverage, the file/state table, reuse dates, omissions,
and checks actually run. Record the source revision and relevant uncommitted
changes so the next run can compare sources. Do not claim that a tool scan or a
successful build proves full coverage.

Remove only temporary files created for this run, stop any capture runner, and
clear temporary status-bar overrides. Preserve unrelated work. Run
`git diff --check` and the repository Stop check. Report the absolute README path,
image count, and material limits. Do not publish to Figma unless requested.
