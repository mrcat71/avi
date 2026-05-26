# Changelog

All notable changes to Avi are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Avi follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
