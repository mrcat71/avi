# Changelog

All notable changes to Avi are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Avi follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- An **Agents** menu in the menu bar. **How to Use Avi with AI Agents…** opens a short guide: install the skill, open the repository once, the Codex sandbox setting, prompts to copy, and the line that makes handing commits to Avi your agents' default. **Install Agent Skills…** opens Settings > Agents, which now links to the guide as well. Both are also in the Help menu.
- Delete Tag now asks whether to delete the tag only here or on the remote too. Delete Locally keeps the pushed copy, as before. Delete Locally and from 'origin' deletes the remote tag first, so if the remote refuses, for example because the tag is protected, the local tag stays for you to retry. The remote is the one Push Tag uses, and only the tag is matched, never a branch with the same name.

### Changed
- Changes is one screen for one commit or several; the Files | Plan switch is gone. Unstaged files sit on top and, under them, **Commits** lists what you are about to commit: Commit 1 is your staged files, and planned commits from agents, the AI, and you stack under it. Drag files between commits or use Move To: into Commit 1 stages, back to Unstaged unstages, and planned commits never touch the index. **Split into Commits…** in the toolbar has the AI group every change into planned commits, and Commit 1 has its own **Split…**. With one commit you just press Commit; with several, **Commit All** makes Commit 1 first and the planned ones after it, and **Commit This** makes only the selected one. AI > Split Staged Into Commits… is replaced by these.

## [0.4.2] - 2026-09-26

0.4.1 was tagged but never published, so its fixes ship in this release.

### Fixed
- Avi 0.4.0 quit as soon as an AI action started: writing a commit message, splitting staged changes, rewording, revising a plan, or checking the AI settings. The release was built with Swift 6.3, which miscompiles `Task.sleep(for:)` when more than one module calls it ([swiftlang/swift#86204](https://github.com/swiftlang/swift/issues/86204)), so the task aborted the moment its timeout sleep ended. Avi now sleeps through the Swift runtime's clock, which also fixes the other waits that used it: settings saves, hover popovers, and Git lock retries. A test fails if `sleep(for:)` comes back, and the release workflow now runs `--self-test`, including the AI check, on the packaged app before publishing it.
- Waiting for an AI command could resume twice when the command exited just as Avi started waiting for it, which also crashed.
- An AI tool that hangs on `--version` no longer stalls the check that runs before every AI action and in Settings > External Tools > Test. Avi gives up after 5 seconds, as intended.

## [0.4.0] - 2026-09-23

### Added
- Plan mode in Changes. A Files | Plan switch shows pending commits grouped by who proposed them: an agent session, Avi's AI, or you. Drag files between commits or use Move To, check each file's full change against HEAD, edit every message, then Commit All (Cmd+Return) to create them in order, or Commit This (Option+Cmd+Return) to take them one at a time. Each commit takes exactly its files with `git commit --only`, so anything else staged stays staged. If a hook or Git stops the run, the commits already made stay and the rest of the plan waits.
- Right-click a planned commit, or use its "…" button, for the same menu: commit it now, have the AI write its message, revise or split it with the AI from your own instructions, move it, merge it with a neighbour, or delete it. Rethink Plan with AI… reworks every commit at once from what you tell it. The composer shows the main ones as buttons: Write Message, Revise…, Split…, Arrange, and Rethink Plan….
- Agents can hand work to Avi. The new `avi` command talks to Avi over a local socket: Claude Code, Codex, or any other agent sends one commit (Avi stages its files and fills the commit field) or several (they land in Plan). Nothing is committed until you approve it. Several sessions can work at once, across repositories or in the same one: a session's new proposal replaces only its own drafts, files another session holds are refused, and your edits are never overwritten without the agent asking. Avi marks tabs with new proposals and counts them on the Dock icon instead of switching tabs on you. See `docs/AGENT-INTEGRATION.md`.
- Settings > Agents, also reachable from Help > Install Agent Skills…, installs the `avi` command in `~/.local/bin` and the `avi` skill for Claude Code and Codex, and shows whether Avi is listening. `[agents] enabled` in the config turns the socket off.
- Discarding changes works on a multi-file selection. A discard started from a row that is part of the selection applies to every selected file, and the confirmation names the count and lists the paths. Cmd+Shift+D discards the selected unstaged files from anywhere in the window, and the shortcut is rebindable like the other global ones.

### Changed
- AI jobs (splitting staged changes, rewording, splitting or recomposing commits) run in the background under a banner with a Cancel button, instead of a sheet that blocked the whole window. The old sheet's Cancel did not stop the AI either.
- The status line under the toolbar no longer repeats the unpushed and unpulled counts that the Push and Pull buttons already show.
- The default AI model is `gpt-6-luna`. A config file with a blank `model` now uses it too; a model you set stays as it is.
- AI > Split Staged Into Commits… now fills Plan mode instead of a separate sheet, so you review the split with diffs and can move files around. Paths the AI names that are not staged are left out with a note instead of failing the whole split. Splitting or recomposing existing commits from History keeps its sheet.
- Stage, unstage, discard, and diff pass file paths to Git literally, so a name containing `*`, `?`, or `[` affects only that file.
- A new folder shows each of its files in the Changes list instead of one folder entry, so its files can be staged and planned one by one. Discarding them removes the folders they leave empty.
- A multi-file discard runs as a single `git restore` instead of one process per file, with untracked files deleted in the same action.

### Fixed
- On macOS 14 and later, a vertical line from the diff's line-number gutter ran through the file name above every diff.
- AI prompts no longer fill in `${...}` placeholders that appear inside your diff, which garbled the prompt for changes to shell scripts or templates.
- Splitting staged changes refused to run in repositories where a long-finished rebase had left `.git/REBASE_HEAD` behind. Only a rebase that is actually in progress blocks it now.

### Security
- Agents can only use repositories you have opened in Avi. For any other repository Avi asks you first, because opening a repository runs Git in it and a repository's config can make Git run programs, which would let a sandboxed agent escape its sandbox through Avi.

## [0.3.0] - 2026-09-22

### Added
- Worktree support. A repository with linked worktrees lists them in the sidebar with their branch and any locked or prunable state, and opening one adds it as its own tab.
- Branches already checked out in another worktree are marked as such, and their checkout is disabled instead of failing. Git's refusal, if it is still reached, now explains which worktree holds the branch.

### Fixed
- Gone-branch cleanup could not delete anything in the common case. A squash-merged branch has no commits in the current branch, so Git refuses the safe delete, and the result was a page of repeated Git hints. A gone upstream already means the remote dropped that branch, so the refused ones are now force-deleted in the same confirmed action, locally only. Any remaining failure is reported as one line per branch.
- A linked worktree kept showing stale branches and history, because its refs live in the main repository's git directory and nothing there was being watched.
- Commands run from sibling worktrees now share one queue slot, since they write the same refs.

## [0.2.2] - 2026-09-15

### Added
- Double-click a branch in the sidebar to check it out.
- The Branches section header offers a cleanup action for local branches whose upstream is gone from the remote. It appears only when such branches exist, confirms first, and keeps the current branch plus anything Git reports as unmerged.
- Tags now offer Push Tag and Delete Tag from their context menu, in the sidebar and on history badges. Push names the remote it will publish to and warns that pushing only the tag uploads its commit outside every branch. Delete removes the local tag and leaves any pushed copy on the remote.

### Changed
- The push sheet states whether pushing updates an existing remote branch, adopts one that already exists, or creates a new one and sets it as upstream.
- Local branches are listed by name, with only the default branch pinned to the top. Checking out a branch no longer reorders the list.
- Starting a remote operation while another is still running now explains why nothing happened instead of ignoring the click.

## [0.2.1] - 2026-09-15

### Fixed
- Avi downloaded from a GitHub release crashed immediately on launch. Bundled resources were resolved through SwiftPM's `Bundle.module`, which only finds its bundle on the machine that built the app; they now load from the app bundle through `Bundle.main`.
- Release archives no longer replace `Lottie.framework`'s internal symlinks with duplicate files, which left the downloaded app with a code signature that failed verification.

## [0.2.0] - 2026-09-14

### Added
- Native selectable diff text with Find support, horizontal scrolling, and separate old/new line-number gutters.
- Explicit confirmation before checking out a tag. Clicking a sidebar reference inspects its commit without changing the working tree.

### Changed
- Refreshed the Changes and History workspaces with a compact toolbar, repository tabs, a resizable commit composer below the diff, and bounded file-list widths.
- Repository sessions now deduplicate canonical paths, stop background observation when closed, and coalesce overlapping refresh requests.
- AI staged splits validate the complete file partition and staged snapshot before applying, reject unsupported working-copy states, and execute as one queued operation. Partial failures are reported without automatic retry or rollback.
- Single-commit rebases preserve descendant commits and reject non-linear history or a changed rebase plan.

### Fixed
- AI Reword now checks the actual HEAD instead of using the first all-branches history row. Rewording HEAD changes only its message without including staged files, and target checks and rewriting share one Git command queue slot.
- Diff text could disappear beneath the line-number ruler or start horizontally clipped after opening a zero-sized pane or switching files.
- History could collapse to a narrow column with no commit selected; commit details and the Changes composer could consume excessive space.
- The history graph now releases trailing empty lanes after branches end or merge, while preserving active lane positions and incoming connections.
- Staged and unstaged selections now retain their own diff source, and stale asynchronous diff/detail responses no longer replace a newer selection.
- Annotated tags now navigate to and display their peeled commit rather than the tag object.
- The GONE badge aligns with the branch name and stays on one line in narrow sidebars.
- Zero-height history rows produced repeated AppKit warnings.
- Git command queues now share canonical repository paths, clean up completed tasks, propagate queued cancellation, and limit lock retries to replay-safe commands.

## [0.1.4] - 2026-06-02

### Fixed
- Git operations could intermittently fail with "Unable to create '.git/index.lock': File exists" (or "another git process seems to be running") when an automatic refresh, the repository picker, overlapping keyboard shortcuts, or an AI commit apply ran two git commands against the same repository at once. All git commands for a given repository are now serialized, so these spurious lock errors no longer occur; different repositories still run concurrently.

## [0.1.3] - 2026-05-31

### Added
- Click a stash in the sidebar to open its contents - the changed files and each file's diff - in the main pane, mirroring the commit detail view.
- The commit panel now shows a clear "Generating commit message..." indicator with a Cancel button while an AI commit message is being generated.

### Changed
- Staging or unstaging several selected files now runs a single git command and one status refresh instead of one per file, so large selections are no longer slow.
- After staging or unstaging (from the pane button, the per-row +/- button, or the right-click menu), the selection moves to the next file in the list so you can keep working without re-selecting.
- Pull now fetches all remotes (with prune) before merging, so remote-tracking refs, ahead/behind counts, and deleted-on-remote ("gone") branches stay current.
- Branches whose upstream was deleted on the remote are flagged with a red icon and a red "GONE" badge instead of subtle orange text.
- The changed-files list uses git status letters (M, A, D, R) instead of pencil/plus/minus icons.

## [0.1.2] - 2026-05-26

### Added
- Local changes view now uses two resizable panes (Unstaged on top, Staged on bottom) with clearly labeled "Stage" and "Unstage" buttons in each header.
- Protected branch (detected from `origin/HEAD`, with a `main`/`master` fallback) is now always pinned to the top of the local branches list.

### Changed
- Stage and Unstage buttons act on the files selected in their pane and are disabled until you select something. The old "stage everything" fallback is gone — explicit selection only.
- Whichever pane has no files (e.g. Staged when you haven't staged anything yet) now collapses to a thin header strip so the populated pane gets the full height.
- In tree mode, all folders default to expanded. Collapses you make stick for the rest of the session; folders that appear later (new directory of changes) are auto-expanded too. Folder-expansion state is no longer persisted across launches.
- "Create Branch" sheet now replaces spaces with hyphens as you type, so branch names stay valid without surprise rejections from git.

## [0.1.1] - 2026-05-26

### Added
- Sidebar "Stashes" section listing all stashes, with right-click menu for Apply, Pop (apply and drop), and Drop (with confirmation).
- Right-click "Push and Open Pull Request" / "Push and Open Merge Request" on local branches: pushes the branch (setting upstream when needed) and opens the GitHub/GitLab compare page with the title pre-filled.

### Changed
- History scope now defaults to "All branches" so newly opened repositories show the full graph. The filter menu still lets you switch back to current-branch scope.
- AI commit menu uses a neutral `character.bubble` icon instead of the sparkles/wand "magic" iconography.
- Removed the duplicate branch status pill from the repository action toolbar; the sidebar branches list is the single source of truth.

### Fixed
- Default Codex command template now includes `--skip-git-repo-check`, so AI commit generation works in newly opened repositories without per-repo trust configuration.

## [0.1.0] - 2026-05-22

### Added
- Git UI: tab-based repository view, status bar, branch and remote info.
- Local changes: staged/unstaged file list with Fork-style ordering, per-file diff view, selection-preserving stage/unstage with subtle animation.
- History view with commit graph and per-commit file diff.
- File tree with default-expanded folders, expand-all / collapse-all actions, and per-repository expansion memory.
- AI commit message generation via command or OpenAI backends. IDE-style debug drawer (resizable, scrollable, copy/clear, Escape to close, auto-open only on error or timeout).
- Config file support: auto-creation of the config directory and file on first launch, live reload via file watcher, secrets routed to the macOS Keychain.
- Repository picker replacing the welcome screen, with search, lazy metadata hydration (branch, dirty state, last-opened), context menu actions (Reveal in Finder, Open in Terminal, Copy Path, Remove from Recent), and `+`-button re-entry as a sheet.
- GitHub / GitLab integration groundwork: Personal Access Token authentication, `gh` and `glab` CLI detection, and clone-from-provider flow via the provider CLIs with `git clone` as a fallback.
- Settings sections for General, Appearance, Git, Clone, GitHub, GitLab, AI Commit Messages, External Tools, and Advanced; navigation subtitle showing the config file path; CLI status badges for `gh` and `glab`.
- `--version` and `--self-test` CLI flags on the `AviApp` binary for CI smoke testing.
