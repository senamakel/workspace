# workspace

Personal dotfiles / agent config. `install.sh` symlinks most files into `$HOME`
and builds shared agent sources into native harness formats. This repo remains
the source of truth, so source changes appear in `git diff`.

## Layout

| Repo path | Installed to |
|---|---|
| `RULES.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.codex/CODEX.md`, `~/.config/opencode/AGENTS.md` (one shared rules file, linked into every agent) |
| `agents/<name>/` | Canonical agent metadata and instructions; `install.sh` builds both harness formats |
| `claude/settings.json` | `~/.claude/settings.json` (hooks, statusline, plugins) |
| `claude/mcp.json` | `~/.claude/mcp.json` |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` |
| `skills/<name>/` | `~/.claude/skills/<name>`, `~/.codex/skills/<name>` (one canonical source) |
| `bin/*` | on PATH via the repo `zshrc` (no symlinks) |
| `codex/hooks.json` | `~/.codex/hooks.json` |
| `zshrc` | sourced from `~/.zshrc` via an appended loader line |

`RULES.md` is the single source of truth for agent instructions: it is
symlinked into each agent's own instructions file (Claude's `CLAUDE.md`,
Codex's `AGENTS.md`/`CODEX.md`, opencode's `AGENTS.md`), so all three always
share the same rules. Edit `RULES.md` and the change is live for every agent
(re-run `install.sh` only if a link is missing).

`agents/` is the single source of truth for reusable subagents. Do not edit the
generated cache or installed harness files; edit `agent.json` or
`instructions.md`, then re-run `install.sh`.

`skills/` is the single source of truth for reusable skills. Each
`skills/<name>/` contains a `SKILL.md` and any optional `scripts/`,
`references/`, `assets/`, or `agents/openai.yaml` resources. The same directory
is linked into Claude and Codex.

`zshrc` holds only custom functions and aliases. `~/.zshrc` and `~/.zshenv`
remain local machine-specific files (oh-my-zsh setup, PATH exports, tool
installer snippets); `install.sh` keeps a marker-guarded `source` line in
`~/.zshrc` pointing at the repo `zshrc`.

`~/.codex/config.toml` is deliberately not synced: it mixes machine state
(project trust list, marketplace caches, desktop theme) with at least one
embedded API key, which must not be committed. Likewise
`~/.config/opencode/opencode.jsonc` (and the `node_modules`/`package.json`
opencode keeps beside it) stays local — only `AGENTS.md` is synced.

## Install

```sh
./install.sh --dry-run   # preview
./install.sh             # apply
```

The script is idempotent and non-interactive. Anything it replaces is moved
to `~/.config-backups/workspace-<timestamp>/` first. Run it from the primary
checkout (not a `worktrees/` checkout) so links survive worktree cleanup.

## Adding things

- New agent: add `agent.json` and `instructions.md` under
  `agents/<agent-name>/`, then run `./install.sh`. It builds native files into
  `~/.config/workspace/generated-agents/` and links them into both harnesses.
  Use `bin/build-agents --check` to validate sources without installing them.
- New skill: add `skills/<skill-name>/SKILL.md`, keep bundled resources inside
  that directory, run `bin/check-skills`, then re-run `./install.sh`.
- New slash command: create `claude/commands/`, add it to `install.sh` the
  same way agents are handled, and re-run.

## Shared Agents

- `pr-contribution-triager` decides whether a PR is a genuine, repo-aligned
  contribution or applies `needs-manual-review`.
- `pr-approval-reviewer` performs final technical review. It approves only a
  fully inspected, green, stable revision; otherwise it leaves one actionable
  non-blocking review comment.
- `pr-unit-test-reviewer` maps changed behavior to truthful regression
  assertions, identifies misleading or missing tests, and evaluates
  compatibility and independent verifiability without mutating the PR.
- `pr-babysitter` babysits a PR until it is green and clean, no matter what:
  loops over CI and CodeRabbit/human feedback, fixes failures at the root (never
  skipping hooks or disabling tests), pushes atomic commits, replies-in-thread and
  resolves threads, and keeps going across CI cycles. Run it as a paced main loop
  with `pr-babysit` (below) so it can actually loop; a dispatched subagent returns
  `WAITING_ON_CI` when CI outlasts its session.
- `gh-issue-triager` investigates duplicates and relevance, then either closes
  a high-confidence dropped issue with evidence or enriches an escalated issue
  with a managed, code-grounded implementation plan.

The following workflow agents are adapted from the
[superpowers](https://github.com/obra/superpowers) skill set as dispatchable,
isolated-context subagents:

- `plan-writer` turns an approved spec into a bite-sized, TDD-structured
  implementation plan (exact paths, complete code per step, no placeholders)
  saved to `docs/plans/`.
- `plan-executor` executes a written plan task-by-task in one isolated session,
  following each task's TDD steps and reporting a completion summary.
- `tdd-implementer` implements one well-specified task via strict
  red-green-refactor, commits in scoped slices, self-reviews, and reports
  `DONE` / `DONE_WITH_CONCERNS` / `BLOCKED` / `NEEDS_CONTEXT`.
- `code-reviewer` reviews a completed diff or branch against its plan and
  quality standards, returning calibrated Critical/Important/Minor findings and
  a merge verdict without mutating the tree.
- `systematic-debugger` investigates a bug to root cause through a four-phase
  method before proposing any fix, then optionally implements the minimal fix
  behind a failing regression test.
- `completion-verifier` independently verifies a completion claim by running the
  proving commands and reporting evidence-backed pass/fail.

`repo-orchestrator` is the top-level conductor over a whole repository's open
work. It triages every open issue and pull request, classifies each into a bucket
(merge-ready, needs-work, needs-review, needs-triage, can-be-taken-up, blocked),
and routes it to the right `pr-*`/`gh` command or subagent — driving fixes and
taken-up work through isolated worktrees and the review/dev agents, and looping
until the board is in a known state. It merges PRs and starts net-new work only
when explicitly authorized. Spin it up in any harness with `repo-orchestrate`
(see Tools).

`sentry-triager` triages a Sentry project's unresolved issues and routes the
actionable ones into tracked GitHub issues: it dedups against existing issues,
promotes real errors to PII-safe GitHub issues against the upstream repo, links
the two directions (`sentry-link` back-annotates the Sentry issue; the GitHub
body carries the Sentry permalink), and resolves each tracked issue in the next
release. It drives the `sentry-*` helpers (see Tools) and never copies user PII
or secrets into GitHub.

## Shared Skills

Skills live in `skills/<name>/` and are linked into both Claude and Codex.
Alongside `humanizer`, the following workflow skills are adapted from
[superpowers](https://github.com/obra/superpowers) — guidance you follow in the
main loop, several of which dispatch the workflow agents above. `using-superpowers`
is the map that ties the whole arc together.

- `using-superpowers` — the workflow map: which agent or skill to reach for, and
  the `brainstorming → plan-writer → execute → finish` arc.
- `brainstorming` — turn an idea into an approved design/spec before any code;
  hands off to the `plan-writer` agent.
- `subagent-driven-development` — execute a plan by dispatching a fresh
  `tdd-implementer` per task with a `code-reviewer` gate after each.
- `dispatching-parallel-agents` — split 2+ independent problems across
  concurrent subagents.
- `finishing-a-development-branch` — verify tests, then integrate via an
  upstream PR (this repo's conventions; no local merge to `main`).
- `receiving-code-review` — evaluate review feedback technically instead of
  performing agreement.
- `using-git-worktrees` — set up an isolated workspace, preferring the
  `worktree` command.
- `writing-skills` — create or edit a skill as TDD applied to documentation.

## Tools

### `worktree <slug> [--json]`

Creates branch `<slug>` from the current `HEAD` and checks it out at
`<repo>/worktrees/<slug>`. If the matching branch and registered worktree
already exist, the command safely reuses them. It then runs recursive submodule
initialization — cloning GitHub submodules over **SSH** (`git@github.com`)
regardless of the HTTPS URLs in `.gitmodules` (set `WORKTREE_HTTPS=1` to keep
HTTPS) — and returns a stable `WORKTREE_READY` report with the path, branch,
commit, submodule count, and next `cd` command.

```sh
worktree fix-auth-timeout
worktree dependency-audit --json
```

### `atomic-commit [--json] "<scoped message>" -- <path>...`

Creates a commit from an explicit file list. It rejects directories, unchanged
paths, traversal, and implicit catch-all pathspecs; unstages unrelated work
without discarding it; and stages and commits only the named files.

```sh
atomic-commit "bin: add worktree helper" -- bin/worktree .gitignore
atomic-commit --json "docs: explain setup" -- README.md
```

### `pr-list [--json] [--limit <count>] [--include-drafts] [-R|--repo <owner/name>]`

Lists open pull requests for the current repository, preferring its
`upstream` remote over `origin`. **Draft PRs are excluded by default**; pass
`--include-drafts` to list them too. The concise default report includes each
PR's title, shortened body, review state, CI summary, branches, and
mergeability (`can_merge`, `has_conflicts`, `blocked`, `behind_base`, or
`unstable`). Use `--json` for stable, structured agent input, or `--repo` to
inspect another repository from any directory.

```sh
pr-list
pr-list --json
pr-list --include-drafts
pr-list --repo tinyhumansai/openhuman --limit 20
```

### `pr-merge <number> [--dry-run] [--json] [-R|--repo <owner/name>]`

Merges a PR only after a strict preflight: it must be open, out of draft,
approved, conflict-free, `CLEAN`, finished with no failing or pending checks,
and free of active unresolved review threads. The command pins the inspected
head SHA to prevent a concurrent push from slipping past validation. It
squashes by default; use `--merge` or `--rebase` to select another strategy.

```sh
pr-merge 123 --dry-run
pr-merge 123 --repo tinyhumansai/openhuman
pr-merge 123 --json --merge
```

Use `--dry-run` to inspect every gate without changing GitHub. A blocked PR
exits with status 2 and reports every blocker, making the command suitable for
agent decision loops. `--delete-branch` is opt-in.

### `pr-fix <pr-number> [extra prompt text...] [claude|codex|opencode]`

Checks a PR out into `<repo>/worktrees/pr-<n>` (preferring the `upstream`
remote, i.e. the canonical `tinyhumansai/*` repo), merges the base branch in
(conflicts are left for the agent), wires upstream tracking + `pushRemote`
to the contributor's fork so `git push` updates the PR, then launches the
chosen harness (default `claude`) with a fix-the-PR prompt plus any extra
text. When the harness exits you're asked whether to delete the worktree.
Draft PRs are refused by default; set `PR_FIX_ALLOW_DRAFT=1` to work one anyway.
`PR_FIX_SAFE=1` disables the yolo/bypass flags; `PR_FIX_REPO` overrides repo
resolution. Conventions follow `tinyhumansai/openhuman/scripts/shortcuts`.

Harnesses live in a small registry near the top of `bin/pr-fix`
(`HARNESSES` + `harness_launch`); adding another is a one-line name plus a
launch branch. Bypass flags per harness: `claude
--dangerously-skip-permissions`, `codex
--dangerously-bypass-approvals-and-sandbox`, `opencode --auto`.

### `pr-babysit [<PR#>] [claude|codex|opencode|deepcode|deepcode-flash] [-R owner/name]`

Babysits a PR until it is **green and clean, no matter what** — the paced,
main-loop counterpart to the `pr-babysitter` agent. Run it from the PR's checkout
(e.g. after `pr-fix`) on the PR's branch; it resolves the PR from the current
branch when `<PR#>` is omitted, embeds the single-source `pr-babysitter` playbook,
and launches the chosen harness (default `claude`) as a **main loop** that paces
with `ScheduleWakeup` (~270s/tick) across CI runs — fixing failures at the root,
handling CodeRabbit/human feedback, pushing, and re-checking until every required
check passes and no actionable threads remain. Runs within the permission system
(no bypass; `PR_BABYSIT_YOLO=1` opts in). This is the launcher to use when a
dispatched subagent "doesn't loop" — subagents can't wait across long CI or use
`ScheduleWakeup`; this main-loop session can.

```sh
pr-babysit               # babysit the current branch's open PR until green
pr-babysit 123 codex
pr-babysit -R tinyhumansai/openhuman 123
```

### `repo-orchestrate [claude|codex|opencode|deepcode|deepcode-flash] [options] [extra prompt...]`

Spins up the `repo-orchestrator` agent (above) in the chosen harness (default
`claude`) from the repo root. The launched session reviews every open issue and
pull request, classifies each, and then **merges, works, closes, and fixes as
much as it can** — routing to the `pr-*`/`gh` commands and review/dev subagents,
fanning work out to subagents and background jobs, and looping until the board is
in a known state, ending each cycle with a two-table (PRs + Issues) triage ledger.
Prefers the `upstream` remote over `origin`.

**The harness is launched without permission-bypass flags.** The orchestrator acts
strictly within the permission system and never bypasses a prompt, sandbox, or
approval — anything it lacks permission for is surfaced, not forced. (`REPO_ORCH_YOLO=1`
opts into bypass flags, but that defeats the point and is not recommended.)

By default it is authorized to merge gate-passing PRs and to take up ready work;
narrow that per launch: `--triage-only` (triage/prepare/surface only, no
irreversible action), `--no-merge` (everything but merging), `--no-take-up`
(everything but starting net-new work). Add `--sentry` to also run the Sentry
intake (dispatches `sentry-triager` for the repo's bound Sentry project).
`-R owner/name` targets another repo,
`--limit N` hints the PR census; `REPO_ORCH_REPO` overrides repo resolution. Every
merge still passes `pr-merge --dry-run`; drafts are always skipped. Shares the
harness registry shape with `pr-fix`.

```sh
repo-orchestrate                       # review + merge/work/close/fix all open issues + PRs
repo-orchestrate --triage-only         # only triage/prepare/surface
repo-orchestrate codex --no-take-up    # do everything but start new work
repo-orchestrate -R tinyhumansai/openhuman --limit 30
```

For continuous operation, wrap it in the `/loop` skill or a scheduled run — each
tick is one triage cycle.

### Sentry helpers (`sentry-issues`, `sentry-issue`, `sentry-resolve`, `sentry-link`, `sentry-release`, `sentry-repo`)

A small toolkit that turns Sentry into agent-friendly reports and actions,
backing the `sentry-triager` agent. Install the CLI on a new box with
`install-sentry-cli` (official installer, sudo-safe). All share
`bin/sentry-lib.sh` and read the same config `sentry-cli` reads:
`SENTRY_AUTH_TOKEN` (required), `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_URL`
(default `https://sentry.io`; set for self-hosted). The report/issue/resolve/link
tools call the Sentry Web API for structured JSON (`sentry-cli` does not expose
issue data in an agent-friendly form); `sentry-release`'s `new`/`finalize` wrap
`sentry-cli` directly.

**Repo-aware:** the helpers resolve `org`/`project` for the current git repo
automatically, so from inside a bound repo you can drop `--org`/`--project`.
Precedence: flags/env → repo `.sentryclirc` → repo→project map
(`~/.config/sentry/repos.tsv`, override `SENTRY_REPO_MAP`) → `~/.sentryclirc`.
Bind and inspect the current repo with `sentry-repo`.

- `sentry-repo` — show the Sentry context resolved for the current repo;
  `--set <org> <project>` binds it (user map, never touches the repo), `--list`,
  `--unset`, `--write-rc` (write a repo-local `.sentryclirc`), `--json`.
- `sentry-issues [--json] [--status ...] [--query ...] [--limit N] [--stats-period ...]`
  — a project's issues (default unresolved, most frequent first): shortId,
  level, culprit, event/user counts, first/last seen, assignee, permalink.
- `sentry-issue <id|SHORT-ID> [--json] [--frames N]` — one issue's detail:
  exception type/value, culprit, top **in-app** stack frames, and key tags
  (release, environment, handled). User/request context is deliberately omitted
  (possible PII).
- `sentry-resolve <id|SHORT-ID>... [--in-next-release | --in-release <v> | --ignore | --unresolve] [--json]`
  — change issue status; `--in-next-release` is the standard "fix is coming"
  resolution.
- `sentry-link <id|SHORT-ID> <url> [--note ...]` — annotate a Sentry issue with a
  tracking URL (comments→notes fallback for self-hosted).
- `sentry-release list|latest|new|finalize [<version>] [--json]` — release report
  (`list`/`latest` via API) and `sentry-cli` wrappers (`new`/`finalize`).

Spin up the triager itself with `sentry-triage [harness] [--no-resolve]
[--ignore-noise] [-R owner/repo] [--org O --project P]` — the launcher analogue of
`repo-orchestrate`: it runs the `sentry-triager` agent in the chosen harness,
within permissions (no bypass), creating linked GitHub issues and resolving them
in the next release by default. Or fold Sentry into a full repo sweep with
`repo-orchestrate --sentry`.

```sh
sentry-repo --set acme web-app     # bind this repo -> Sentry acme/web-app
sentry-repo                         # show what this repo listens to
sentry-issues --json               # no --org/--project needed once bound
sentry-issue MYAPP-9F --json
sentry-resolve MYAPP-9F --in-next-release
sentry-link MYAPP-9F https://github.com/org/repo/issues/128
```

### `deepcode [claude args...]`

Runs the Claude Code CLI but backed by DeepSeek models through OpenRouter's
Anthropic-compatible endpoint (`https://openrouter.ai/api`). It sets the
`ANTHROPIC_*` routing/model env vars in the wrapper process only and `exec`s
`claude`, so your normal `claude` (pointed at Anthropic) is unaffected. The Opus
tier maps to `deepseek/deepseek-v4-pro` (heavy — coding/deep review); the Sonnet,
Haiku, and subagent tiers map to `deepseek/deepseek-v4-flash`, matching the agent
model tiering so a Sonnet-tier agent stays cheap here too. Override with
`DEEPCODE_MODEL` / `DEEPCODE_FAST_MODEL` (or use `deepcode-flash` to force every
tier onto flash). Because DeepSeek V4's 1M window loses accuracy well before it
fills, the wrapper caps the effective context by setting
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` so sessions auto-compact at ~300k tokens instead
of the ~967k default; override with `DEEPCODE_CONTEXT_WINDOW` (blank it to keep the
model's full window). Requires `OPENROUTER_API_KEY` in the environment (set it in
your `~/.zshrc`, not this repo). All arguments pass straight through to `claude`.

### `workflow-update [--no-commit]`

For workflow superprojects (repos with submodules). Fetches the canonical
remote (`upstream` preferred, else `origin`) and merges its default branch,
then bumps each first-level submodule (no recursion) to the tip of its own
canonical remote's default branch, stages the moved pointers, and commits
them as "Update submodule pointers". `--no-commit` stages only.

## Notes

- The `humanizer` skill was originally managed by the `~/.agents` skill
  manager (see its `.skill-lock.json`). It is vendored here as a plain copy,
  so update it by re-copying from upstream and rerunning `bin/check-skills`.
- `worktree/` and `worktrees/` are gitignored — feature branches may live in
  either convention without polluting repository status.
