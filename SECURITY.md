# Security policy

Avi is a personal project maintained by one person. Reports are handled on a
best-effort basis, and there is no bug bounty.

## Supported versions

Only the latest release listed on the
[Releases](https://github.com/mrcat71/avi/releases) page is supported. Fixes
ship in a new version; published releases are never replaced in place.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: open the **Security** tab of this
repository and choose **Report a vulnerability**. Please do not open a public
issue for a security problem.

Include the affected version (**About Avi** shows it, or run
`Avi.app/Contents/MacOS/Avi --version`), your macOS version, what an attacker
controls in the scenario, and the steps to reproduce.

Expect a first reply within a week. Please give the fix a reasonable window
before publishing details.

## Scope

Avi runs entirely on your Mac and has no backend. The parts worth looking at:

- Handling of GitHub / GitLab tokens and AI provider keys, which are stored in
  the macOS Keychain under service `com.avi` and must never reach the config
  file, logs, or the AI debug drawer.
- Subprocess execution: `git`, `gh`, `glab`, and the configured AI command are
  launched with argument arrays, never through a shell. Anything that turns
  repository content, a branch name, or a config value into an executed
  command is in scope.
- Config and repository parsing, including paths taken from a repository.
- The `openai` AI backend, which sends the staged diff to the configured
  endpoint. Anything that sends repository content anywhere else is in scope.
- The agent control socket (`~/Library/Application Support/Avi/control.sock`,
  mode `0600`, same-user peers only) and the `avi` command. A request may stage
  the files it names, fill a commit message, and create plan drafts in
  repositories you have opened in Avi; it must never commit, push, run a
  command, or make Avi open a repository you did not approve. Anything that lets
  another user, a web page, or a sandboxed agent go beyond that is in scope.
- The installer in Settings > Agents, which writes `~/.local/bin/avi` and the
  agent skills and must not overwrite files it did not write.

Known and out of scope:

- Release bundles are ad-hoc signed and not notarized, so macOS Gatekeeper
  warns on first launch. Verify downloads with the published `SHA256SUMS`.
- Anything that needs an attacker to already run code as your user, since Avi
  is a local application with your own permissions.
