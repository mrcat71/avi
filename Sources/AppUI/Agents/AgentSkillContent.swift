import Foundation
import GitKit

/// The `avi` agent skill, installed for Claude Code and Codex by Avi's
/// installer. The marker line records the app version that wrote it, so the
/// installer can tell an outdated copy from one you edited.
enum AgentSkillContent {
    static let name = "avi"

    static func marker(version: String = GitKit.version) -> String {
        "<!-- avi-skill \(version) -->"
    }

    /// Reads the version from an installed skill's marker, or nil when the file
    /// was not written by Avi.
    static func installedVersion(in text: String) -> String? {
        guard let start = text.range(of: "<!-- avi-skill ") else { return nil }
        let rest = text[start.upperBound...]
        guard let end = rest.range(of: " -->") else { return nil }
        let version = rest[..<end.lowerBound].trimmingCharacters(in: .whitespaces)
        return version.isEmpty ? nil : version
    }

    static func skillMarkdown(version: String = GitKit.version) -> String {
        frontMatter + "\n" + marker(version: version) + "\n" + body
    }

    /// Codex reads display metadata for the skill picker from this file.
    static let codexInterface = """
    interface:
      display_name: "Avi"
      short_description: "Hand finished changes to Avi for review"
      default_prompt: "Use $avi to send my finished changes to Avi as commits to review."

    """

    private static let frontMatter = #"""
    ---
    name: avi
    description: Hand finished work in a git repository to Avi, the macOS git client, instead of committing. Avi stages the files and fills its commit message, or lays out several commits that the user approves with one click. Use when a coding task in a git repository is done and Avi has that repository open, or when the user asks to send changes, a commit, or a commit plan to Avi.
    when_to_use: Trigger on "avi", "send to avi", "hand off to avi", "propose commits", "commit plan in avi", "fill the commit message in avi", and at the end of a coding task when `avi status --json` shows the repository open in Avi.
    allowed-tools: Bash(avi *)
    ---
    """#

    private static let body = #"""

    # Hand work to Avi

    Avi is the user's git client. Instead of committing, send Avi a proposal: Avi
    stages the files and fills its commit message, or lays out several commits for
    the user to review. The user approves every commit in Avi. You never create
    commits yourself.

    ## When to hand off

    Run `avi status --json` from the repository first.

    - Exit code 3 or error `not_running`: Avi is not running. Hand off only when the
      user asked for Avi; `avi propose` starts it.
    - `result.repo.open` is true: the user reviews this repository in Avi. Hand off
      when your task is done.
    - Avi runs but the repository is not open: ask the user before handing off.
      Avi only accepts repositories the user has opened in it; for any other one
      it answers `not_trusted` and asks the user to confirm opening it.

    `result.repo.commitField` and `result.repo.drafts` show what is already
    waiting, including your earlier proposal. Sending again replaces your own
    proposal and never touches another session's.

    ## Build the proposal

    - Read `git status --short` and the diff. Propose only files you changed in
      this session. Leave out other people's work, local configuration, secrets,
      and build output.
    - Group files by logical change. Each file belongs to one commit. Order the
      commits so each one builds on the one before it.
    - Follow the repository's commit conventions. Without any, use Conventional
      Commits: `type(scope): summary` in the imperative, at most 72 characters, no
      trailing period, and a body wrapped at 72 that explains why.
    - Never add AI attribution or `Co-Authored-By` trailers.
    - Paths are relative to the repository root, exactly as `git status` prints
      them. List both sides of a rename.

    Write the plan to a fresh file from `mktemp -t avi-plan` (in Claude Code, fill
    it with the file tool), or pipe it on standard input with `--file -`. Never
    reuse a fixed name in a shared folder such as `/tmp`. Then send it:

    ```json
    {
      "version": 1,
      "title": "Short summary of the task",
      "commits": [
        {
          "message": "feat(parser): accept quoted keys\n\nQuoted keys appear in real configs.",
          "files": ["Sources/Parser.swift", "Tests/ParserTests.swift"]
        },
        {"message": "docs: describe quoted keys", "files": ["README.md"]}
      ]
    }
    ```

    ```sh
    mktemp -t avi-plan        # prints a fresh path; write the plan there
    avi propose --file /path/printed/by/mktemp --json
    ```

    A single commit also fits on the command line. Give `-m` twice for a body;
    list the files after `--`, relative to the current directory:

    ```sh
    avi propose -m "fix(ui): keep the selection after a refresh" -- Sources/UI/List.swift
    ```

    With no files, Avi only fills the message, for whatever is already staged.

    Avi recognizes Claude Code and Codex sessions from the environment. Anywhere
    else, pass `--agent <name> --session <id>` and keep the same session id for
    the whole conversation.

    ## Read the result

    - `placement: commitField`: the files are staged and the message is in the
      commit field.
    - `placement: previewCard`: the user was writing a message; yours waits
      beside it.
    - `placement: plan`: the commits wait as planned commits in Avi's Changes view.

    Tell the user in one line what is waiting, for example "3 commits are waiting
    in Avi for your review."

    Errors come back with `ok: false`, exit code 1, and a `code`:

    - `unknown_path`: a path has no changes. `error.changed` lists every path that
      does; fix the plan and send it again.
    - `duplicate_path`, `empty_message`, `files_required`: fix the plan and send it
      again.
    - `file_claimed`: another session's proposal holds those files
      (`error.owners`). Tell the user; do not take them over.
    - `edited_by_user`: the user edited your earlier proposal in Avi. Ask before
      sending again with `--replace`.
    - `conflicts`: the repository has unresolved merge conflicts. Tell the user.
    - `busy`: Avi is committing in this repository. The command already retried;
      try again later.
    - `not_trusted`: the user has not opened this repository in Avi. Avi is asking
      them to confirm; send again after they do. Never work around it.
    - `disabled`: agent proposals are turned off in Avi > Settings > Agents.

    ## Never

    - Run `git commit`, `git add`, `git restore --staged`, or `git reset` to
      prepare a hand-off. Avi stages exactly what the plan names.
    - Push, or ask Avi to commit for you.
    - Pass `--replace` without the user's OK.

    ## Troubleshooting

    - `avi: command not found`: run `~/.local/bin/avi`, or ask the user to click
      Install in Avi > Settings > Agents.
    - Error `blocked`, or "Operation not permitted" while connecting: a sandbox is
      blocking Avi's socket. In Codex, the command needs network access
      (`[sandbox_workspace_write] network_access = true`) or approval to run
      outside the sandbox.
    - Exit code 3 after `avi propose`: Avi did not start. Ask the user to open it.
    """#
}
