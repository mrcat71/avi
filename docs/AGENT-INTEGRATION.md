# Agent integration

Claude Code, Codex, and other local agents hand finished work to Avi instead of
committing. Avi stages the files and fills its commit message, or lays out
several commits in Plan mode. You approve every commit in Avi; agents never
commit or push.

## Set up

1. In Avi, open **Settings > Agents** (or **Help > Install Agent Skills…**) and
   click **Install All**. This writes:

   | Target | Location |
   | ------ | -------- |
   | `avi` command | `~/.local/bin/avi`, a shim that runs `Avi.app/Contents/MacOS/Avi --cli` |
   | Claude Code skill | `~/.claude/skills/avi/SKILL.md` |
   | Codex skill | `~/.codex/skills/avi/SKILL.md` and `agents/openai.yaml` |

   `~/.local/bin` must be on your `PATH`. If Avi moves, the command shows as
   outdated in Settings; click **Update**. Avi refuses to install the command
   while macOS runs it from a translocated copy: move Avi to `/Applications`
   first. Installing never overwrites a file Avi did not write, or a skill you
   edited, without asking.

   From a terminal, `avi skill status` and
   `avi skill install [--claude] [--codex] [--command] [--force]` do the same;
   before the command exists, run it as
   `/Applications/Avi.app/Contents/MacOS/Avi --cli skill install`.

2. Open each repository the agents work in once in Avi. Agents can only use
   repositories you have opened in Avi (open tabs and the recent list). For
   any other repository Avi answers `not_trusted` and asks you to confirm
   opening it, because opening a repository runs Git in it, and a repository's
   config can make Git run other programs.

3. Codex only: its sandbox must let `avi` reach Avi's socket. Either set
   `[sandbox_workspace_write] network_access = true` in `~/.codex/config.toml`,
   or approve running `avi` outside the sandbox when Codex asks. Codex's
   sandbox keeps `.git` read-only, which is why Avi does the staging.

The skill tells agents when to hand off: after a task, when `avi status --json`
shows the repository open in Avi, or whenever you ask for Avi. To make it the
default, add a line such as "When a task in a git repository is done, hand the
commit to Avi with the avi skill" to your global agent instructions.

## Where a proposal lands

| Proposal | Result |
| -------- | ------ |
| One commit, nothing else pending, nothing else staged | Avi stages exactly its files and fills the commit field. A "Proposed by" banner offers **Withdraw**, which clears the message and unstages what Avi staged. |
| One commit while the field holds your own text | Your text stays. The proposal waits in a preview card: **Replace**, **Append as body**, or **Discard**. |
| Several commits, another session's proposal pending, or other files staged | The commits become drafts in Plan mode. Nothing is staged. A proposal already in the commit field moves into the plan as well. |
| One commit without files | Fills the message only, for whatever is already staged. |

Several agent sessions can work at once:

- Each draft records the agent and session that sent it. When a session sends
  again, its new proposal replaces only its own drafts. If you edited them, the
  request fails with `edited_by_user` unless it passes `--replace`.
- A file held by another session's pending proposal is refused with
  `file_claimed`.
- Requests for one repository (keyed by its worktree path) run one after
  another; different repositories and worktrees run in parallel.
- Avi never switches tabs on its own. A tray icon marks tabs with proposals you
  have not seen, and the Dock badge counts them. `--focus` selects the tab and
  brings Avi forward.

## Plan mode

The **Files | Plan** switch in the Changes toolbar shows the plan: drafts
grouped by who proposed them, then the changed files no draft holds.

- Drag files between commits, or select files and use **Move To** from the
  context menu. Delete moves selected files to Not in Plan.
- Selecting a file shows everything its commit will take: the working-tree
  version against `HEAD`. Files with both staged and unstaged changes are
  marked; the commit takes the whole working-tree version.
- **Commit All** (Cmd+Return) creates the drafts in order. **Commit This**
  (Option+Cmd+Return) creates only the selected one and moves to the next.
  Each draft runs `git commit --only` with exactly its files, so other staged
  changes stay staged. When drafts come from several sources, each group
  header offers **Commit These**.
- Right-click a draft, or use its "…" button or the composer's, for the same
  menu: **Commit This Now**, **Write Message with AI**, **Revise with AI…**,
  **Split with AI…**, **Move Up/Down**, **Merge with Previous/Next**, and
  **Delete Commit**. The plan's own "…" menu has **Rethink Plan with AI…**.
  The composer shows the main ones as buttons under the message.
- The AI actions ask what should change ("put the tests in their own commit",
  "merge the docs into the feature commit"), then replace those drafts in
  place with the AI's answer. They see only those drafts' messages and the
  changes in their files, and files the AI leaves out move to Not in Plan.
  They use your AI settings; the prompt is `ai.planRevisionPromptTemplate`
  in the config file.
- The first failure, such as a rejecting hook, stops the run. Commits already
  made stay; the remaining drafts stay in the plan. Nothing is rolled back.
- **AI > Split Staged Into Commits…** fills the plan with AI drafts. It still
  refuses partially staged files. Splitting or recomposing existing commits
  from History keeps its review sheet.

Plans live in memory: quitting Avi drops them, while files Avi staged stay
staged.

## The `avi` command

```
avi status [--repo PATH] [--json]
avi open [PATH] [--focus] [--json]
avi propose --file PLAN.json|- [--repo PATH] [--agent NAME] [--session ID]
            [--title TEXT] [--replace] [--focus] [--json]
avi propose -m SUBJECT [-m BODY]... [--agent NAME] [--session ID] [--] [FILE...]
avi skill status | install | remove [--claude] [--codex] [--command] [--force]
avi version
```

- A plan file lists commits with paths relative to the repository root:

  ```json
  {
    "version": 1,
    "title": "Short summary of the task",
    "commits": [
      {"message": "feat(parser): accept quoted keys\n\nWhy it matters.", "files": ["Sources/Parser.swift"]},
      {"message": "docs: describe quoted keys", "files": ["README.md"]}
    ]
  }
  ```

  `./path` and absolute paths inside the repository are accepted too. List
  both sides of a rename; for a staged rename either side brings the other.
- `-m` joins its values with blank lines, like `git commit -m`. Files after it
  are relative to the current directory.
- The agent and session come from `--agent`/`--session`, then the plan file,
  then the environment: `CODEX_THREAD_ID` (Codex) or `CLAUDE_CODE_SESSION_ID`
  (Claude Code).
- `propose` and `open` start Avi in the background when it is not running and
  wait up to 15 seconds. `status` never starts it. `busy` and `no_window`
  answers are retried for up to 30 seconds.
- Exit codes: `0` ok, `1` rejected by Avi, `2` usage error, `3` Avi not
  reachable. `--json` prints the raw response.
- `AVI_SOCKET` overrides the socket path, for development builds and tests.

## Protocol

Avi listens on `~/Library/Application Support/Avi/control.sock`. A client sends
one JSON request on one line and reads one JSON line back:

```text
{"v":1,"method":"propose","params":{"repo":"/abs/worktree","agent":"Codex","session":"t1","commits":[{"message":"...","files":["a.swift"]}]}}
{"v":1,"ok":true,"result":{"app":{"version":"0.4.2"},"placement":"plan","commits":1,"staged":[],"notes":[],"repo":{...}}}
```

Methods are `status`, `open`, and `propose`. `status` lists open repositories,
their counts, the commit-field proposal, and pending drafts with their agent
and session. Failures carry `error.code`:

| Code | Meaning |
| ---- | ------- |
| `unknown_path` | A path has no changes; `error.changed` lists the paths that do. |
| `duplicate_path`, `empty_message`, `files_required`, `no_commits` | The plan itself is invalid. |
| `file_claimed` | Another session's proposal holds the files; `error.owners` names it. |
| `edited_by_user` | You edited this session's earlier proposal. |
| `conflicts` | The repository has unresolved conflicts. |
| `not_trusted` | You have not opened this repository in Avi; Avi is asking you. |
| `busy` | Avi is committing in this repository. |
| `no_window` | Avi is starting and has no window yet. |
| `not_a_repository`, `disabled`, `unsupported_version`, `bad_request`, `failed` | As named. |

The command adds two codes of its own: `not_running` (nothing listens on the
socket) and `blocked` (a sandbox or permissions refused the connection).

## Security

- The socket is mode `0600`, and Avi checks each peer's user ID, so only your
  own processes can connect.
- A proposal can open a repository you already trust, stage the files it
  names, fill a commit message, and create drafts. It cannot commit, push, or
  run a command. Paths reach Git as literal pathspecs.
- Turn it off in **Settings > Agents > Accept proposals**, or with
  `[agents] enabled = false` in the config file.

## Troubleshooting

- **`blocked`, "Operation not permitted" when Codex runs `avi`**: Codex runs
  commands without network access, and its sandbox then denies unix sockets
  too. Enable `network_access` as above, or approve running `avi` outside the
  sandbox.
- **`not_running` although Avi is open**: the Avi version running predates
  0.4.0, or **Accept proposals** is off. The Socket row in Settings > Agents
  shows whether Avi is listening.
