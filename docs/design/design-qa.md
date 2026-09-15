# Native design verification

Selected targets: [Changes](variants/02-commit-bottom.png) and
[History](variants/03-history.png).

Implementation is in progress. Full-screen visual fidelity is **not verified**.
The user confirmed a successful manual build on 2026-09-09 after pulling the
Renovate updates. Later gutter and shell changes still need a complete rebuild.

## Checks completed

- GitKit compiles directly with Swift 6 for the macOS 14 target.
- The AppKit diff document type-checks independently. Standalone assertions cover
  line numbers, addition/deletion markers, attributed highlighting, and empty text.
- Standalone core assertions cover full replay sequences, invalid plans, refusal
  to overwrite a mismatched synthetic todo, queue serialization, cancellation,
  and recovery. These checks do not run Git mutations.
- The refresh coordinator type-checks independently. A standalone concurrent
  request test verifies serialized reads, completion, and subsequent refreshes.
- Swift parser checks pass for AppUI and test sources. This is not a type-check
  or execution of the Swift Testing suites.

## Verification blocker

SwiftPM cannot execute its manifest sandbox in the current session. The existing
manual `./build.sh` fallback compiles GitKit, but AppUI's Swift macro plugin fails
with `sandbox-exec: sandbox_apply: Operation not permitted`. This also occurred
before source changes. The user's normal-terminal build succeeded; the sandbox
restriction remains local to agent-side full compilation. No sandbox bypass was used.

The user's History screenshot confirmed missing diff text, not merely a capture
artifact. The ruler received a dirty rectangle wider than its own bounds and
painted over the document. Its drawing now clips to the ruler bounds. A complete
native scroll-container render now shows code, highlighting, and line numbers.
A pixel regression checks that an oversized dirty rectangle cannot repaint the
adjacent document. Whole-application visual verification remains incomplete.

The reported `setRowHeight` warnings were reproduced with a zero
`defaultMinListRowHeight`. Removing that override eliminates the warnings in
the native list harness; explicit 24/28-point history row frames remain.

The new gutter uses [NSRulerView](https://developer.apple.com/documentation/appkit/nsrulerview)
and UTF-16 row metadata outside the text storage. Numbers no longer enter copied
or searched text. The independently compiled component and standalone assertions
pass with warnings treated as errors.

Run `./build.sh` from a normal terminal to obtain a full build result. After a
successful build, validate the following in a disposable fixture repository:

- Changes: a file modified in both index and worktree, switching sides, rapid
  selection, multi-select, batch selection advancement, and error recovery.
- Diff: long lines, Unicode, large files, copy across hunks, native find, binary
  files, empty diffs, and keyboard focus. Confirm that copying/searching excludes
  gutter numbers and that the ruler stays aligned during horizontal scrolling.
- History: dense graphs, long refs, resize behavior, stable graph columns,
  repeated refresh without losing the selected file, and failed diff loads.
- Tabs: repeated open, symlink aliases, close-last-tab, switching while another
  repository opens, and restoring each repository's selected workspace.
- Both appearances and density settings at the minimum window size and a larger
  desktop size. Compare actual captures against both targets before sign-off.

History detail now bounds the file pane to 220-360 pt instead of leaving its
maximum width unconstrained. A standalone native SwiftUI/AppKit layout fixture
reproduced the original 750/749 pt split at 1500 pt and measured 360/1139 pt with
the fix. Moving the divider to 240 pt, resizing the window to 700 pt, and
expanding it again passed geometry assertions. The fixture render was inspected;
this verifies the split constraints, not the complete History screen. The
updated application still needs a normal rebuild and visual confirmation.

History's no-selection state also needs explicit full-width frames on both
vertical split panes and their container. A native fixture reproduced the
reported collapse to 400 pt when selection was cleared. With the frames applied,
both panes remained at the workspace width through empty, selected, deselected,
narrow (760 pt), and expanded (1500 pt) states. `HistoryLayoutTests` adds a
full-AppUI empty-state resize regression test; it has only been syntax-checked
here because full AppUI compilation remains blocked in the agent sandbox.

Changes now bounds the normal commit composer to 190-280 pt and lets the diff
fill the remaining height. The upper bound is removed while generation, a
preview, an error, or the debug drawer is visible. The form content scrolls so
its footer remains reachable when auxiliary content exceeds the available space.
A native layout fixture measured 719/280 pt for diff/composer in a 1000 pt pane,
allowed the expanded composer to resize to 549 pt, and verified that the footer
can be scrolled fully into view with both long AI content and debug output in a
500 pt pane. The fixture covered six layout states. Actual AI interactions and
keyboard focus still need validation in the rebuilt application.

Annotated tags now retain their tag object ID separately from the target ID
reported by `for-each-ref`'s `%(*objectname)`. Sidebar navigation, graph badges,
commit tooltips, and Copy Commit SHA use the target. This fixes `v0.1.3` resolving
to tag object `74e339e45c17` instead of commit `3c0d652ba6d6`.

Direct Swift 6 GitKit compilation and standalone parser assertions passed.
Read-only checks compared all five repository tags against `git rev-parse
<ref>^{}` and found every target in the loaded history. A native 100-row List
fixture verified programmatic selection and scrolling to rows 50, 90, and 5,
then clearing selection, without redundant detail-load requests. Checked-in
parser tests were updated but only syntax-checked here. The user's subsequent
screenshot confirms navigation to `v0.1.3` and restored annotated-tag badges.
Loading targets outside the current history window or filter remains separate work.

The follow-up checkout error came from graph badges invoking checkout on an
ordinary click. Sidebar tags had the opposite mismatch: their Checkout menu
item invoked selection. Both now use `ReferenceActionButton`: primary clicks
and Show Commit inspect, while checkout is an explicit menu action. Tags require
confirmation explaining detached HEAD and warning about local changes. No
automatic stash, discard, force, or retry is introduced. Git's refusal to
overwrite local changes remains intact, as described in
[git-switch](https://git-scm.com/docs/git-switch).

Tag checkout passes the reviewed target OID after `--`, not a short name that
could resolve to a branch or a tag moved since confirmation. Three recording-
executable XCTest cases verify target arguments and refusal propagation without
invoking Git. Five native XCTest cases exercise the actual shared button,
including a parent context menu, primary clicks for all ref kinds, Show Commit,
tag cancellation/confirmation, and explicit branch checkout. All eight passed;
test compilation also passed with warnings treated as errors. GitKit and the
shared component compile for macOS 14. Full-AppUI compilation still fails at
the sandboxed Observation macro plugin. Native alert image capture returned
blank content, so it is not visual sign-off; confirm the integrated menu and
dialog in a normal application rebuild.

The next screenshot exposed clipped line prefixes on initial diff load. A native
fixture reproduced `scrollRangeToVisible` running before the panel had a size:
the clip origin stayed at x=17 instead of x=-80, placing text under the ruler.
`DiffScrollView` now waits for a usable viewport before resetting to the document
origin, accounting for the clip view's ruler insets. Later resizing preserves
the user's scroll position rather than repeatedly resetting it.

Six `NativeDiffViewportTests` pass against the actual diff component, covering
initial overlay/legacy scrollers, replacement after scrolling, changing gutter
width, collapsed panels, resize, short/empty documents, and a top inset. Before
the fix, three of the original four cases failed. The component and tests compile
for macOS 14 with Swift 6; tests compile with warnings treated as errors. A native
render was inspected with both number columns, full prefixes, additions,
deletions, and Unicode visible. Full AppUI syntax checking and Git diff whitespace
checks pass. Integrated application compilation and visual confirmation still
require a normal rebuild; the user's existing manual build artifacts were not
changed.

The current branch still contains legacy repository, AI, settings, and operation
code. It must not be presented as a finished full rewrite or release candidate.
