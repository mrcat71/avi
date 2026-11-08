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
| `appearance`     | Theme (`system`, `light`, `dark`), row density, the diff's font (`diffFont`, any installed monospaced family; `SF Mono` is the system one) and text size (`fontSize`, 11 to 16; diffs use one point less), file-list mode (tree / flat), graph lane width, and `authorPictures`: show author pictures beside their names in History, from the GitHub or GitLab account that wrote each commit (asked with a token from Settings or your `gh` or `glab` sign-in), else looked up by address there and on Gravatar (default `true`; `false` shows the names alone and contacts no server). |
| `git`            | `defaultAuthorName` and `defaultAuthorEmail`: who commits in repositories where Git has no `user.name` or `user.email`; a repository's own identity and `includeIf` ones always win. `signCommits`: sign every commit, as Git's `commit.gpgSign` does; `false` leaves it to Git. `fetchInterval`: minutes, `0` turns auto-fetch off. `autoRefresh`: refresh when files change; `false` refreshes after Avi's own commands and when you come back to Avi. `pruneOnFetch`: fetch with `--prune`, or `--no-prune` when `false`. `externalEditor`: the app or command **Open in Editor** uses; empty uses the first installed editor Avi knows. `terminalApp`: the app **Open in Terminal** uses; empty uses Terminal. |
| `clone`          | Default clone directory, and whether a clone starts on HTTPS or SSH.    |
| `ai`             | AI commit-message backend (command / openai), model (default `gpt-6.1-luna`), prompts, limits, timeout. `conventionalCommits` fills `${style}` in the prompts; see [Prompts](#prompts). |
| `agents`         | `enabled`: accept proposals from local agents through the `avi` command. See [`AGENT-INTEGRATION.md`](AGENT-INTEGRATION.md). |
| `pullRequests`   | How pull request titles are made from branch names, and whether new requests start as drafts. See [Pull request titles](#pull-request-titles). |
| `externalTools`  | `gitPath`, `ghPath`, `glabPath`, `codexPath`, `claudePath`: an executable here replaces the one Avi finds. Without one, Avi runs `/usr/bin/git`; `codexPath` and `claudePath` apply to AI command templates that start with `codex` or `claude`. A path that names no executable is ignored. `diffToolPath` is the tool **External Diff** opens; empty uses Git's `diff.tool`. Merge-tool selection is described below. |
| `advanced`       | `historyLimit`: commits History loads at first, 50 to 5000; more load as you scroll. `verboseLogging`: log every Git command with its exit status and time to the system log (Console, subsystem `com.svinarenko.avi`, category `git`). Commands can hold file paths and commit messages. |
| `integrations`   | Provider accounts (PAT + CLI). Tokens themselves are in the Keychain.   |

The TOML decoder is intentionally tolerant: missing keys decode to their
defaults, unknown keys are dropped silently. Old config files keep working
across upgrades unless a key is renamed. A blank `ai.model` also decodes to the
default model, since no backend accepts an empty one. `externalTools.editorPath`
and `externalTools.terminalPath` are no longer read; a value in them moves to
`git.externalEditor` and `git.terminalApp` when those are empty.

Settings shows the keys most people never change under **Advanced** at the
end of each section. They are the same keys; only the window hides them.

## Merge tools

**Settings > External Tools > Merge tool** chooses the tool **Merge Tool** in
Changes opens for a conflicted file. `externalTools.mergeTool` is empty to use
Git's `merge.tool`, a preset id such as `vscode`, `cursor`, or `goland` to use
that app, or `custom` to run `externalTools.mergeToolCommand`.
`externalTools.mergeToolPath` overrides a preset's executable path.

A custom command runs in a shell with `$BASE` (the common ancestor), `$LOCAL`
(Current), `$REMOTE` (Incoming), and `$MERGED` (the output file). Quote these
variables to support paths containing spaces. Avi waits for the tool to exit;
Git marks the file resolved if the output changed. Closing without merging
leaves the conflict unresolved. During a rebase, Current is the upstream and
Incoming is the commit being replayed, not the reverse. Git's temporary copies
stay outside the working tree, and no `.orig` backups are left beside the file.

## Pull request titles

The Push sheet makes a pull or merge request's title from the branch name,
and you can edit it there before creating the request. Folders such as
`feature/` or a user name are dropped, unless the folder is itself a ticket
key or a kept name; then it leads the title. Every `-` and `_` becomes a
space, except inside:

- Ticket keys: an upper-case project, a hyphen, and a number (`INFRA-12345`,
  `OPS2-7`). Projects listed in `ticketPrefixes` match in any case and are
  written in capitals, so `infra-123` becomes `INFRA-123`.
- Hyphenated file and folder names of the repository, while
  `learnNamesFromRepository` is on, such as `environments/k8s-infra-ah-ams1/`.
  Extensions are ignored, and the repository's own name counts too. The
  longest name wins.
- `keepHyphenated` entries, matched in any case and only on whole words: a
  name, a pattern where `*` stands for one word of letters, digits, and dots,
  or a regular expression between slashes.

```toml
[pullRequests]
ticketPrefixes = ["INFRA", "OPS"]
keepHyphenated = ["k8s-*-*-ams1", '/[a-z0-9]+-[a-z]{3}[0-9]+/']
learnNamesFromRepository = true
capitalize = false   # capitalize the first word that is not a ticket key or kept name
draft = false        # start new requests as drafts
```

With these rules `feature/INFRA-12345-upgrade-k8s-infra-ah-ams1-ingress`
becomes `INFRA-12345 upgrade k8s-infra-ah-ams1 ingress`, and `fix-login-timeout`
becomes `fix login timeout`. Write regular expressions in single-quoted TOML
strings, which keep backslashes as they are. **Settings > Git > Advanced >
Pull Request Titles** edits the same keys and shows the title for a branch
name you type; names learned from a repository apply only in the Push sheet.
`draft` and `capitalize` are under **Settings > Git > Pull Requests**.

Avi creates the request with `gh` or `glab` when you are signed in to that
host, else with the token from Settings > GitHub or GitLab, else it opens the
filled-in form in your browser.

## Prompts

`promptTemplate` writes commit messages, `rewordPromptTemplate` rewrites one,
`splitPromptTemplate` groups changes into commits, and
`planRevisionPromptTemplate` changes planned commits as you ask. **Settings >
AI Commit Messages > Advanced > Prompts** edits each one and lists the
`${name}` placeholders it gets; an unknown placeholder stays as written.

`${style}` asks for `type(scope): summary` subjects while `conventionalCommits`
is on, and plain imperative ones while it is off. The built-in prompts use it;
add it to your own to make the switch apply to them. A prompt that is still
exactly a built-in one from an earlier Avi is read as today's built-in one, so
an unedited config file follows the switch too.

## Update settings

The update switches in **Settings → General** are not in `config.toml`.
Sparkle, which installs Avi's updates, keeps them in Avi's user defaults
(`com.svinarenko.avi`): `SUEnableAutomaticChecks` for the daily check and
`SUAutomaticallyUpdate` for installing in the background. To set them from a
script or dotfiles:

```sh
defaults write com.svinarenko.avi SUEnableAutomaticChecks -bool false
```

## Clone folders

With `clone.rememberDestinationPerProvider` on, a clone from a host starts in
the folder the last clone from that host went to, while it exists. Avi keeps
those folders in its user defaults under `avi.clone.lastFolderByHost`, not in
`config.toml`; a host it has no folder for starts in `clone.defaultDirectory`.

## Workspace restoration

Open repository paths, tab order, and the selected repository are saved in
macOS user defaults under `avi.workspaceSession`, separately from the recent
repository list and `config.toml`. Each open worktree is saved as its own path;
worktrees of one repository reopen in that repository's tab. Changes are saved as tabs are opened,
selected, reordered, or closed, not only when Avi quits.
If several repository windows are open, the most recently changed window
provides the saved workspace.

On launch, Avi reopens the saved tabs once. A repository that cannot be opened
is skipped and reported without preventing the others from reopening. A saved
tab whose folder no longer exists, such as a worktree removed while Avi was
closed, is dropped without a report; while Avi runs, a tab closes as soon as
its folder is deleted. If the saved selection is unavailable, Avi selects the
first restored repository. Closing every tab leaves the repository picker on
the next launch.

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
