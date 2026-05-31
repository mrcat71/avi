# Changelog

All notable changes to Avi are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Avi follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Click a stash in the sidebar to open its contents - the changed files and each file's diff - in the main pane, mirroring the commit detail view.
- The commit panel now shows a clear "Generating commit message..." indicator with a Cancel button while an AI commit message is being generated.

### Changed
- Staging or unstaging several selected files now runs a single git command and one status refresh instead of one per file, so large selections are no longer slow.
- After staging or unstaging (from the pane button, the per-row +/- button, or the right-click menu), the selection moves to the next file in the list so you can keep working without re-selecting.

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
