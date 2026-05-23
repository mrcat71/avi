# Configuration

Avi stores its on-disk settings in a TOML file under the standard macOS
Application Support directory.

## File location

| Platform | Path                                                  |
| -------- | ----------------------------------------------------- |
| macOS    | `~/Library/Application Support/Avi/config.toml`       |

Avi creates this file (and its parent directory) on first launch using the
built-in defaults from `AviConfig` (`Sources/AppUI/Config/AviConfig.swift`).
A missing file is treated as a fresh install, not an error.

If the file cannot be written (permission error, read-only volume), Avi
surfaces a banner in **Settings → General** and keeps the in-memory defaults
so the app stays usable.

## Live reload

Avi watches the config directory via `ConfigWatcher`. Edits made by other
tools - your text editor, `chezmoi`, `dotfiles` syncs - are picked up within a
second and re-rendered into the UI. The app ignores file-system events from
its own writes to avoid a feedback loop.

## Schema overview

The full schema is defined as a Codable struct in
[`Sources/AppUI/Config/AviConfig.swift`](../Sources/AppUI/Config/AviConfig.swift).
A complete example with every section is in
[`config.example.toml`](../config.example.toml).

| Section          | Purpose                                                                 |
| ---------------- | ----------------------------------------------------------------------- |
| `appearance`     | Theme, density, font sizes, file-list mode (tree / flat), graph width.  |
| `git`            | Default author identity, fetch interval, auto-refresh, terminal/editor. |
| `clone`          | Default clone directory, protocol preference, gh/glab vs git fallback.  |
| `ai`             | AI commit-message backend (command / openai), prompts, limits, timeout. |
| `externalTools`  | Override paths to `git`, `gh`, `glab`, `codex`, `claude`, editors.      |
| `advanced`       | History limit, verbose logging.                                         |
| `integrations`   | Provider accounts (PAT + CLI). Tokens themselves are in the Keychain.   |

The TOML decoder is intentionally tolerant: missing keys decode to their
defaults, unknown keys are dropped silently. Old config files keep working
across upgrades unless a key is renamed.

## Secret storage

Avi never writes secrets to the config file. The macOS Keychain (service
`com.avi`) holds:

- GitHub and GitLab Personal Access Tokens, keyed by account UUID
  (`avi.account.<uuid>`).
- The OpenAI API key, keyed as `avi.openai.apiKey`.

`gh` / `glab` CLI-backed accounts store **no** token in the app: Avi shells
out to the CLI on demand and lets it manage its own credentials.

## Editing the file manually

The file is small and human-readable; editing it by hand is supported. Live
reload picks up changes without restarting the app. If you break the syntax,
**Settings → General** shows the underlying parser error and Avi keeps the
last good in-memory copy.
