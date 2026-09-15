# Avi rewrite

The user selected a full application rewrite on 2026-09-08, with Fork as the
primary interaction and visual reference. This is an implementation brief, not
a claim that the new application has been built or verified.

## Direction

- Build a native macOS Git client, not a web dashboard or a marketing prototype.
- Keep Swift, SwiftUI, and the Git executable as the default technologies.
  Use AppKit where text selection, tables, or split-pane behavior requires it.
- Replace the current application state, operation execution, and workspace UI.
  Merely splitting `RepositoryStore` into extensions is not a rewrite.
- Preserve the existing macOS 14 deployment target unless a concrete feature
  requires an explicitly approved change.
- Use Fork as an interaction reference, with Avi's own branding and assets.
  The user supplied dark-mode Changes, repository manager, and History screens.
  The user selected concepts 2 and 3 as the preferred visual direction.
- Preserve the current config path, Keychain service, account data, repository
  data, and uncommitted user work. Do not launch migration code against them
  during development checks.

## Workspace design

The selected visual targets are `design/variants/02-commit-bottom.png` for
Changes and `design/variants/03-history.png` for History. Both use the same
repository tabs, sidebar, restrained surfaces, and compact toolbar. The
interaction model is:

- Repository tabs and one compact toolbar for branch and remote operations.
- A persistent sidebar for local changes, history, branches, tags, and stashes.
- Changes: unstaged and staged file lists, a large diff, and a commit composer.
- History: a readable commit graph and table, with selected commit files and diff.
- Resizable panes, stable keyboard focus, multi-selection, and contextual actions.
- One semantic token system for typography, density, surfaces, selection, and
  status colors. No independent legacy and glass palettes.
- Light and dark appearances with restrained decoration. Code and lists use
  legible content surfaces; translucency is not the primary visual treatment.
- AI actions stay attached to the operation they assist. Diagnostics remain
  available without occupying the default workspace.

### Reference research

Reviewed official public materials on 2026-09-08. The user's Fork screenshots
are the directly inspected visual baseline. Other clients were researched through
official documentation; live browser inspection and local screenshot downloads
were unavailable in this execution environment. The ideas below are design
proposals, not claims from hands-on testing of those clients.

| Reference | Useful pattern for Avi | Boundary |
| --- | --- | --- |
| [Tower](https://www.git-tower.com/help/guides/first-steps/tower-overview/mac) | File overview beside diff, explicit repository navigation, back/forward | Do not replace fast repository tabs with an extra navigation step |
| [Gitfox](https://www.gitfox.app/) | Compare revisions, word-level diff highlights, line/hunk staging | Do not copy branding or expand the minimum OS requirement just for appearance |
| [GitKraken](https://help.gitkraken.com/gitkraken-desktop/interface/) | Configurable graph columns and collapsible reference sections | Keep agent, team, and issue-management surfaces out of the default Git workspace |
| [GitButler](https://docs.gitbutler.com/overview) | Explicit grouping of changes before committing | Parallel branch lanes change repository semantics; do not adopt that workflow implicitly |
| [GitHub Desktop](https://github.com/apps/desktop) | A focused review-and-commit flow | Preserve Avi's branch graph and multi-repository workflow |
| [Sublime Merge](https://www.sublimemerge.com/) | Code-focused review and granular staging | Keep Avi's native macOS interaction conventions |

Keep Fork's density and persistent context. Explore clearer selection contrast,
more usable diff height, and a composer that does not permanently reduce the
review area. In a clean repository, show a compact clean-state explanation
instead of two large empty staged/unstaged panels. Use neutral fixture data in
new concepts rather than reproducing workplace details from reference images.

## Ownership boundaries

Names below describe responsibilities, not a requirement to add a package for
every responsibility. Start with the existing Swift package and avoid a new
dependency unless a measured need justifies it.

| Owner | Responsibility | Must not own |
| --- | --- | --- |
| App session | Open repositories, active tab, window-scoped command routing | Git parsing or credentials |
| Repository session | Repository identity, shared refs/status, child state lifetimes | View geometry or AI prompt construction |
| Changes state | Staged/unstaged selection, diff requests, commit draft | History pagination or provider login |
| History state | Scope, graph pages, commit and file selection | Working-copy mutation orchestration |
| Operation coordinator | Mutation exclusion, progress, cancellation, errors, refresh invalidation | Presentation code |
| Git execution | Subprocess lifetime, output, command-specific retry, repository paths | UI state |
| AI service | Input snapshot, generation, validated preview | Applying unapproved output directly |
| Platform services | Config, Keychain, accounts, external tools, filesystem events | Global navigation notifications |

Reuse existing tests and data models as compatibility evidence, not as a reason
to retain unsafe implementation details. Existing provider APIs can be temporary
adapters while their implementations are replaced.

## Operation invariants

- Identify the working tree, Git directory, and common Git directory explicitly.
  Do not assume `.git` is a directory or that a path string identifies a lock.
- Serialize conflicting operations across all sessions for the same repository.
  Reserve an entire multi-step mutation, not just each subprocess independently.
- Retry only commands whose failure state is known to permit another attempt.
  Preserve actual error details and lock paths; never remove locks automatically.
- Propagate cancellation. Specify which running operations can stop safely and
  which must settle before releasing the operation reservation.
- Coalesce filesystem events and invalidate only affected data. Retain an event
  arriving during a refresh so it is not silently lost.
- Use request identities to prevent an old response from replacing a newer
  selection. Include repository, path, and staged/unstaged source in diff identity.
- Keep commit drafts and selection stable across refreshes and tab changes.
- Keep each operation's error local to its outcome. A successful background
  refresh must not erase an unrelated operation failure.
- Confirm destructive actions with the exact target and effect. Do not retry
  multi-step history rewrites based only on a substring in stderr.
- Preserve the complete replay sequence when editing an older commit. Validate
  affected commits, working-copy state, and recovery before applying AI previews.
- Apply only a preview validated against the current repository snapshot. An AI
  file list must not broaden the user's selected changes or stage newer edits.

## Feature parity checklist

All items remain pending for the rewrite. The old application is not replaced
until each retained workflow has an implementation and relevant verification.

- [ ] Open, close, switch, and reopen repositories; picker and recent repositories.
- [ ] Clone workflows, provider accounts, and external-tool entry points.
- [ ] Correct staged/unstaged/untracked/renamed/deleted/conflicted file handling.
- [ ] File trees, multi-selection, batch stage/unstage, and selection advancement.
- [ ] Unified diff, binary/empty/error/loading states, and selectable text.
- [ ] Commit drafts, commit, amend, and explicit discard confirmation.
- [ ] History scopes, merges, graph continuity, commit metadata, and file diffs.
- [ ] Branch checkout/create/rename/delete and upstream management.
- [ ] Tags and explicit remote operations with visible progress and errors.
- [ ] Stash inspection, apply, pop, and confirmed drop.
- [ ] AI message generation, cancellation, previews, and diagnostics.
- [ ] Safe AI reword/split/recompose with complete history preservation.
- [ ] Settings, config reload, Keychain compatibility, and custom shortcuts.
- [ ] Light/dark modes, density, accessibility, and keyboard navigation.
- [ ] App bundle startup, version reporting, and non-mutating smoke checks.

Diff enhancements such as side-by-side display, word-level highlighting, search,
and hunk staging are separate acceptance items. They must not obscure missing
baseline behavior or appear as nonfunctional controls in a finished build.

## Delivery and verification

1. Select a visual target for Changes and History using the supplied Fork screens
   and the bounded reference research above.
2. Establish deterministic fixtures and regression tests for the operation
   invariants, especially history preservation and staged/unstaged selection.
3. Implement new execution and state boundaries behind a temporary compatibility
   seam. Keep the existing entry point working until the replacement is ready.
4. Build the complete Changes workflow, then History, repository navigation,
   remote/stash workflows, settings, and AI workflows.
5. Compare native rendered screens with the selected target. Exercise keyboard
   focus, resizing, long paths, large diffs, empty repositories, and failure states.
6. Switch the default entry point only after parity checks pass; then remove
   superseded code. Do not ship parallel unfinished applications as completion.

Tests use controlled fixtures and fake providers. Any Git mutation integration
tests require permission under the active execution policy and must never target
the user's checkout. Render tests must make actual assertions with committed
baselines, not merely instantiate a view.

Current validation limitation: SwiftPM tests were blocked by the execution
environment's sandbox during the initial review. A new design or a passing
format check is not evidence that the application builds or its workflows work.

### Implementation checkpoint: 2026-09-09

Implemented, but not yet verified as a complete native application:

- `WorkspaceSession` owns opening, deduplication, selection, and closing tabs.
  Repository navigation selection stays with the repository rather than the view.
- Changes has source-aware staged/unstaged selection and stale diff response
  rejection. History has request identities for filters, commits, and files.
- `RefreshCoordinator` batches concurrent reads. A request arriving during a
  refresh waits for a subsequent snapshot instead of returning stale entries
  to stage/unstage selection advancement.
- The diff reader uses a selectable AppKit text document with native find support,
  line numbers, change markers, and explicit loading/error presentations.
- History uses compact graph/message/author/SHA/date rows. Main content surfaces
  no longer use glass layers; Changes reserves more width for the diff.
- The command queue resolves symlink aliases, removes completed tails, and
  propagates cancellation to queued work. Lock retries are bounded and restricted
  to selected replay-safe commands; cancellation ends backoff.
- Linear rebase planning preserves descendants and rejects merge/nonlinear
  ranges. The sequence editor refuses a different live replay sequence before
  replacing Git's todo. Its configuration follows the
  [Git rebase documentation](https://git-scm.com/docs/git-rebase).

Verified: direct Swift 6 GitKit compilation; a standalone harness for replay
planning, synthetic todo editing, queue serialization/cancellation/recovery;
native diff document type-check and text/highlight assertions; Swift syntax
parsing and whitespace checks; standalone refresh serialization and completion
assertions. No Git mutation integration tests were executed.

Still required: full AppUI type-check/build, native screenshot comparison,
interaction/accessibility tests, extraction of remaining repository/AI state,
compound-operation exclusion across stores and linked worktrees, process-level
cancellation, stash request identities, stale AI-preview validation, and the
feature parity checklist above. This checkpoint is not the completed rewrite.

### Follow-up after dependency updates

The user pulled the six commits through `5b6c711` and reported a successful
manual build. Those commits update Lottie to 4.6.1 and CI configuration; they do
not alter application source. The manual build omits SwiftPM dependencies via
existing `canImport` fallbacks, so it does not verify the Lottie upgrade itself.

Subsequent work separates diff line numbers into a native ruler, adds UTF-16
offset tests, and moves tabs into the content column beside the full-height
sidebar. These later edits have independent component compilation and parser
checks, but still require a full rebuild and native screen comparison.

Annotated-tag navigation now uses the target object rather than the tag object,
following [Git's ref field semantics](https://git-scm.com/docs/git-for-each-ref/2.50.0.html).
History reveals programmatic selections without reloading an already selected
commit. Read-only checks passed for all five repository tags; native selection
and scroll checks passed independently. Targets outside the loaded or filtered
history still need a dedicated loading path.

Graph ref badges and sidebar tags now separate inspection from checkout through
one shared button. Tag checkout requires confirmation and uses the reviewed
target OID. Eight focused native/recording-executable tests passed without real
Git mutations; integrated application validation remains subject to the build
blocker recorded in [design QA](design/design-qa.md).

### Staged split safety checkpoint

`StagedCommitPlan` now validates a complete file-level partition of the reviewed
staged diff. Applying it through `CLIGitProvider` holds one command-queue slot
across preflight, unstaging, staging, and commits. Other Avi providers using the
same canonical working-tree path cannot interleave commands in that sequence.

Preflight rejects changed previews, missing or duplicate files, empty groups or
messages, partially staged files, renames, conflicts, and unfinished Git
operations. AI filenames use Git's
[`--literal-pathspecs`](https://git-scm.com/docs/git) option. Reviewed diffs include
full blob IDs and disable text conversion, following
[Git diff options](https://git-scm.com/docs/git-diff).

The UI consumes a preview before applying it and rejects duplicate Apply calls.
A partial failure reports completed commits and refreshes status without an
automatic retry or destructive rollback.

Verified with direct Swift 6 GitKit compilation and eight focused XCTest cases,
including a recording executable that simulates Git responses and command
failures. The execution checks never invoke real Git or create commits. AppUI
has a syntax check only for this checkpoint and still needs a full rebuild.

This protection currently covers staged splitting, not historical AI splits or
other compound operations. It does not lock external Git processes, editors,
hooks, or linked worktrees sharing refs. Preview validation is not an atomic
filesystem snapshot; external edits can still race application. These boundaries
remain open rewrite work, not a transaction or rollback guarantee.
