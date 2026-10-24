# Remove Python from repository scripts

Status: implemented on 24 October 2026. The sections below record the approved
scope and original estimates.

## Goal and scope

Run repository build, release, and screenshot commands without Python or Pillow.
Use Swift and system frameworks and libraries from the Xcode SDK
that the project already requires. Keep shell scripts for command orchestration.
Do not add a package dependency or link script code into the app or data package.

Before migration, the checkout had three Python files and two inline commands:

| Current use | Swift replacement | Callers to update |
| --- | --- | --- |
| `scripts/backup_candidate.py` | `scripts/backup_candidate.swift` | Makefile release, archive, and upload recipes; `ci_scripts/ci_post_xcodebuild.sh` |
| `scripts/check_backup_device.py` | `scripts/check_backup_device.swift` | Makefile `release-verify` recipe |
| Simulator JSON parsing in Makefile and `ci_scripts/ci_pre_xcodebuild.sh` | `scripts/select_simulator.swift` | Both callers |
| `.codex/skills/my-screenshots/scripts/check_images.py` | Swift helper in the same directory | Screenshot skill and `screenshots/README.md` |

Website preview is outside this migration. Keep the existing Python command in
`sites/README.md`.

## Estimated code size

The three Python files contained 181 physical lines, including comments and blank
lines. Simulator selection adds two inline Python commands. These are estimates
for equivalent Swift behavior, not measured implementation results:

| Area | Current lines | Estimated replacement lines |
| --- | ---: | ---: |
| Candidate and archive checks | 67 | 130–180 |
| Device evidence check | 20 | 30–45 |
| Simulator selection | 2 inline commands | 50–80 |
| Screenshot checks and contact sheets | 94 | 180–260 |
| Simulator compile-cache launcher | — | 20–30 |
| Total implementation | About 183 | About 410–600 |

Allow a further 200–350 lines for fixture tests and their runner. The total is
about 610–950 lines, or a net increase of about 430–770 lines before documentation
and small caller/CI edits. The Python helpers had no dedicated test files, so the
test increase also adds coverage.

Most growth comes from explicit process/file error handling, JSON types, argument
parsing, pixel-buffer setup, and drawing contact sheets. Keep the helpers small
and separate; a shared command framework or new Swift package is not needed.

## 1. Replace the release checks

Use Foundation for JSON, property lists, files, and Git process execution. Use
CryptoKit for incremental SHA-256. Call the scripts through `xcrun swift`, as the
existing App Store Connect scripts do.

Preserve these release rules:

- Keep `capture`, `check`, `attest`, and `verify-archive`, their arguments, receipt
  paths, JSON fields, and failure exit status.
- Hash tracked and untracked non-ignored source files. Exclude `sites/`. Preserve
  deleted-file markers, relative path order, UTF-8 path bytes, NUL separators,
  symbolic-link handling, and chunked file reads.
- Keep `clinical-backup-receipt.json` out of the archive hash. Preserve the
  current archive traversal rules, including links and nested receipt filenames.
- Read old candidate files and receipts. Match their hash contract; JSON
  whitespace and key order do not affect verification.
- Reject missing, unreadable, malformed, or mismatched evidence. Require the JSON
  boolean `true` for `releaseOnDevice`. A number or string must not satisfy it.
  Match both client IDs and the callback scheme against `Info.plist`.
- Keep the local and Drive checks in one sequential Make recipe. Preserve both
  archive checks around `release-verify` before upload, including with `make -j`.
- Keep credential values out of errors and logs.

Changing the source files changes the candidate hash. Old archives will therefore
need a new build after migration. Do not bypass this rule to retain an archive.

Before deleting the Python files, record expected hashes and results from small
synthetic fixtures. Use these as fixed Swift test data. Cover changed and deleted
source files, ignored files, website-only edits, Unicode paths, symbolic links,
archive mutation, missing receipts, and invalid device evidence. Use synthetic
credentials only. Runtime tests must not need Python.

## 2. Share simulator selection

Decode `simctl` JSON with Foundation. Give the selector two explicit modes:

- Local: preserve the current choice of a booted iOS simulator, then the named
  device on the requested runtime. Preserve an explicit `SIMULATOR_ID` override.
- Xcode Cloud: preserve the choice of the first available iOS iPhone. Do not
  require the local default device name or OS version.

Print only the UUID to stdout. Keep errors on stderr. An empty local choice must
reach the existing `check-simulator` error; a failed Cloud choice must stop the
archive gate.

Use a small shell launcher with the existing architecture checker's compile-cache
pattern. Cache under the worktree's Git metadata, include the compiler identity
and version, and replace compiled files atomically. Keep simulator selection lazy
and evaluate it once per Make invocation. Commands such as `make data-test` must
still work on Linux without Xcode or a simulator.

Test both modes with saved JSON: multiple runtimes, booted devices, fallback
selection, unavailable devices, no match, and invalid input. Test the explicit
UUID override and paths that contain spaces.

## 3. Replace screenshot checks

For the screenshot helper, use ImageIO and Core Graphics for PNG decoding and
pixel buffers, CryptoKit for duplicate checks, and AppKit for contact-sheet text.
Keep the directory argument, `--size`, `--sheets`, `--report`, JSON report fields,
absolute sheet paths, and nonzero status for errors or duplicate images.

Keep duplicate detection based on decoded RGBA pixels and dimensions. Encoded PNG
bytes can differ for identical images. Use a fixed color space and pixel layout,
and force full decoding so damaged image data does not pass a metadata-only
check. Test transparency and color-profile cases against the current results.

Keep the current sheet layout: four columns, at most twelve images per sheet,
240 by 480 thumbnail bounds, labels, and JPEG output. Exact JPEG bytes and font
rasterization do not need to match Pillow. Inspect sheets from the existing PNGs
to check orientation, colors, labels, and clipping. Keep all reference PNGs intact.
Test empty input, invalid PNG data, mixed dimensions, invalid `--size`, and equal
pixels with different PNG encodings.

## 4. Update callers, documentation, and CI

Replace each Python implementation and its callers together. Delete the old
files after their replacement checks pass. Do not retain Python launchers.

- Update screenshot commands in the skill and README. Remove Python/Pillow setup.
- Update `ci_scripts/README.md` where needed.
- Remove the stale `.codex/hooks/README.md` note about `check_comments.py`; that
  file is absent from the current checkout. Keep the working Swift hook.
- Preserve historical validation records, including earlier Python syntax checks.
- Add `scripts/test_scripts.sh` for the new macOS script tests. Follow the current
  architecture checker test pattern: compile Swift test executables in a temporary
  directory and remove them at exit. Use compile conditions to separate CLI entry
  points from tests. Keep each small helper's types with its implementation.
- Run this test command in the existing macOS CI job. Leave Linux package and
  architecture checks independent of CryptoKit, AppKit, and Xcode.

## Completion checks

1. Run the new fixture tests, architecture checks, and existing comment checks.
   Review preserved comments and run `git diff --check`.
2. Run screenshot validation on the existing image set and inspect its sheets.
3. Exercise simulator selection and a local build. Check release recipe ordering
   and rejection paths with synthetic inputs; do not upload or distribute a build.
4. Run the new helpers with a controlled PATH that has no Python. Confirm that no
   build, release, or screenshot command or setup instruction requires Python,
   Pillow, or pip. The website preview command and historical records can still
   name or use Python.

A local check cannot prove Xcode Cloud execution or physical-device OAuth. Report
those checks separately if they are not run; keep all existing release gates.

## Implementation result

The migration adds no dependencies or SwiftPM targets. Website preview keeps its
existing command. After Swift formatting, the four Swift helpers and simulator
launcher have 610 lines. Fixture tests and their shell runner have 498 lines.
These totals include comments and blank lines; caller and documentation changes
are separate.

Validation used fixed legacy hash and pixel fixtures, a full-checkout source hash
comparison, and synthetic command checks with Python absent from PATH. The
screenshot helper checked the existing 48 PNGs at 1206 by 2622 pixels and produced
four contact sheets for visual inspection. No screenshots were recaptured.

The local app build, architecture checks, comment checks, and script tests passed.
Xcode Cloud distribution and physical-device OAuth were not run for this migration.
