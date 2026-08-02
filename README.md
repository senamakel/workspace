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
| `workflows/*.json` | `~/.medulla/workflows/<file>.json` (one link per flow) |
| `open-source/` | Git-backed repository catalog and per-issue contribution queue shared by every machine |
| `bin/*` | on PATH via the repo `zshrc` (no symlinks) |
| `bin/super-review` | `~/super-review.sh` |
| `bin/workspace-tmux` | `~/bin/mosh-tmux` (installed by `workspace-init`) |
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

`workflows/` is the single source of truth for shared Medulla workflow
definitions. Each `<name>.json` is linked individually into
`~/.medulla/workflows/`, rather than linking the directory itself, so Medulla
can keep unmanaged machine-local flows in the same directory. Edit the JSON in
the repo and the change is live; re-run `install.sh` after adding a new file.

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

## Workspace bootstrap and tmux

Initialize the workflow checkout set on the current Mac:

```sh
workspace-init --dry-run
workspace-init
workspace-init --workspace /another/work
```

The default root is `~/work`. The command recursively clones missing
`workflow-openhuman`, `workflow-medulla`, `workflow-tinyplace`,
`workflow-opencompany`, and `workflow-dashboard` repositories over SSH.
Existing destinations are skipped without inspection or updates.

The bootstrap also installs `~/bin/mosh-tmux` as a link to
`bin/workspace-tmux`. A conflicting destination is backed up under
`~/.config-backups/` first.

On the Mac mini, `~/bin/mosh-tmux` creates or reuses the dedicated `mosh` tmux
server's `workspace` session. It provides a six-pane 2×3 window for every
workflow repository, followed by `btop` and `shell`. It reapplies the blue
remote theme and `C-z` prefix before attaching. Override its server and session
names with `MOSH_TMUX_SERVER` and `MOSH_TMUX_SESSION`.

The local `~/super-review.sh` link is managed by `install.sh`. It opens the five
four-pane workflow windows, the mixed `libraries` window, `btop`, Robot1
`cloud`, Mac mini, and shell windows. **It deliberately kills and recreates any
existing `super-review` tmux session.** Run `~/super-review.sh --help` to view
the warning without changing tmux state.

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
- `open-source-researcher` refreshes the approved target-repository catalog
  using popularity, current activity, external-contributor acceptance, low
  issue contention, and local verification fit. It never selects issues.
- `open-source-issue-triager` inspects highly recent issues in approved targets
  and queues only unassigned, collision-free, bounded, reproducible candidates
  with an exact verification plan. It never comments or starts implementation.
- `open-source-contributor` is the execution-only conductor. It claims durable
  queue records, drives target-repository work through native TDD/review
  subagents, opens upstream PRs from the contributor fork, and babysits them
  until green. It never researches repositories or invents work.

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
- `doc-writer` (Sonnet tier) documents changed source — in-code doc comments on
  public APIs and folder/module overviews — matching the repo's conventions and
  changing docs only, never behavior. Wired into the coding pipeline
  (`subagent-driven-development`), the `pr-babysitter` loop, and the orchestrator's
  build flow.
- `code-reviewer` reviews a completed diff or branch against its plan and
  quality standards, returning calibrated Critical/Important/Minor findings and
  a merge verdict without mutating the tree.
- `systematic-debugger` investigates a bug to root cause through a four-phase
  method before proposing any fix, then optionally implements the minimal fix
  behind a failing regression test.
- `merge-conflict-resolver` (Opus tier) resolves git merge/rebase/cherry-pick
  conflicts by reconstructing the 3-way picture and integrating both sides'
  intent — never blindly taking one side — then verifies the result builds and
  tests pass and completes the operation. The orchestrator routes `has_conflicts`
  PRs to it.
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
Alongside `humanizer`, the following workflow skills provide guidance for the
main loop, several of which dispatch the workflow agents above.

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

### `afplay [arguments...]`

Provides portable notification audio for Claude/Codex hooks. On macOS it
delegates unchanged arguments to `/usr/bin/afplay`. On Linux it ignores the
macOS sound path and emits one terminal BEL through `/dev/tty`; SSH and mosh
carry that bell back to the local terminal without a reverse tunnel or daemon.
If no TTY exists, it exits successfully and silently.

Set `AFPLAY_OUTPUT=silent` to disable fallback bells or
`AFPLAY_OUTPUT=stdout` when a caller deliberately wants BEL on standard output.
The fallback never evaluates arguments or runs a configurable callback.

### `open-source-agent <research|triage|contribute> [harness]`

Runs one explicit stage of the open-source contribution pipeline:

```sh
open-source-agent research --limit 20
open-source-agent triage codex --limit 10
open-source-agent contribute --limit 5
```

Repository discovery is manually triggered. The triager consumes only active
catalog entries, and the contributor consumes only its durable issue queue.
Each number is a ceiling, not a quota. The launcher defaults to the
`deepcode-flash` harness (DeepSeek V4 Flash on every tier), and to unattended
execution for deliberately started runs. Pass another harness name to override
it, `--safe` to retain permission prompts, or `--dry-run` to inspect the
complete prompt. Contribution runs additionally enforce a shared ceiling of
five newly opened upstream PRs per UTC day, based on durable issue records.
Existing PRs may still be resumed and babysat after the daily opening allowance
is exhausted.

Shared state lives in `open-source/repositories.json` and one
`open-source/issues/<owner>--<repo>--<number>.json` record per issue. Validate it
with `bin/check-open-source-state`. State claims are pushed before target work
starts, so a same-record rebase conflict safely gives the claim to one machine.
Use `open-source-work repos|queue|show` to inspect state, `prepare` to create a
claimed external worktree, and `run` to execute commands inside that target
without relying on the harness launch directory.

### `worktree <slug> [--json]`

Creates branch `<slug>` from the current `HEAD` and checks it out at
`<repo>/worktrees/<slug>`. If the matching branch and registered worktree
already exist, the command safely reuses them. It then runs recursive submodule
initialization via `submodule-init` (below) — shallow, over SSH — and returns a
stable `WORKTREE_READY` report with the path, branch, commit, submodule count,
and next `cd` command. `WORKTREE_DEPTH` and `WORKTREE_HTTPS` are this command's
names for `submodule-init`'s two knobs and keep working.

```sh
worktree fix-auth-timeout
worktree dependency-audit --json
```

### `submodule-init [<dir>] [--quiet]`

Recursive submodule initialization, shared by every command that prepares a
checkout — `worktree`, `pr-fix`, `open-source-work`, `workflow-remotes`, and the
`res` shell function — so the policy lives in one place.

Git stores a linked worktree's submodule git dirs under
`.git/worktrees/<name>/modules/`, never the shared `.git/modules/`, so a plain
`submodule update --init --recursive` re-downloads every submodule even though
the primary checkout already holds the objects. On `workflow-medulla` that was
~900 MB of network transfer per worktree across 28 nested repositories. This
command instead **borrows objects locally**: each clone is pointed with
`--reference` at whichever repository the primary checkout already has, matched
first by position in the tree and then by `owner/repo` across every configured
remote — `origin` is routinely a personal fork while `.gitmodules` records the
canonical upstream, so one key is not enough. Shallow repositories are screened
out, because Git refuses to borrow from them.

Siblings are initialized concurrently (`SUBMODULE_JOBS`, default 4), since the
elapsed time is per-repository latency and checkout rather than CPU. Together
these took a cold `worktree` on `workflow-medulla` from **4m55s to 28s**, with
the worktree's git dirs down from ~880 MB to 39 MB and identical recursive
gitlinks. `SUBMODULE_REFERENCE=0` disables borrowing.

Anything with no local source is cloned at `--depth 1`, which is the difference
between seconds and minutes on the workflow superprojects. A shallow fetch can
miss the recorded gitlink when it is not reachable from a branch tip, so a failed
shallow pass is **retried at full depth**: the checkout is never left
half-initialized to save time. Set `SUBMODULE_DEPTH=0` to skip the shallow
attempt, or to another integer to change the depth.

Borrowing means the worktree's submodules read objects from the primary
checkout's `.git/modules`, the same trade-off `git clone --reference` makes.
Removing a worktree is unaffected; do not delete or aggressively prune the
primary checkout while worktrees are live.

GitHub submodules are cloned over **SSH** (`git@github.com`) regardless of the
HTTPS URLs in `.gitmodules`; the `-c` overrides travel via
`GIT_CONFIG_PARAMETERS`, so they apply to every nested clone too, with no edits
to `.gitmodules` or global config. Set `SUBMODULE_HTTPS=1` to keep the recorded
URLs. Outside a repo, or in one without `.gitmodules`, it is a silent no-op, so
callers can run it unconditionally.

`workflow-update` uses it only for the **nested** level: it still selects and
resets each direct submodule itself, from several remotes and at full history,
then hands the resulting checkout to `submodule-init` so the nested gitlinks
that moved with it are brought along.

### `box [<name>] [--takeover] [--mosh]`

Attaches to the persistent tmux workspace on a remote box over ssh, running the
remote `mosh-tmux` helper so the six-pane session is built on first attach and
reused afterwards. Names match loosely — `box mini`, `box mac-mini`, and
`box mm` all reach the same machine. With no name it lists every box and its
session state. `--takeover` detaches other clients first, so the session sizes
to the current terminal rather than the smallest attached one; `--mosh` connects
over `mosh` instead of `ssh`. `zshrc` adds `df`, `mini`, and `r1` as shorthands.

`box --list` prints the canonical ssh targets, which is where `sync.sh` reads
the box list from.

```sh
box                    # who's up, and what's running
box dragonfly
box r1 --takeover
```

### `worktree-clean [--dry-run] [--force] [--root <dir>]`

Reclaims the disk space held by finished worktrees. It walks `<root>` (default
`~/work`, or `$WORKTREE_CLEAN_ROOT`) for repositories with a `worktrees/`
directory — superprojects **and submodules**, whose `.git` is a file rather than
a directory — and removes each registered worktree that has nothing left to lose:
no uncommitted changes and no commits missing from a remote — checked both in
the worktree and in every submodule beneath it, so a submodule feature branch
that was never pushed keeps its worktree alive. Unsafe worktrees are kept and
the reason is printed. Branches are never deleted, only their working trees, and
the worktree registry is pruned afterwards. `--force` removes kept worktrees
anyway, destroying that uncommitted and unpushed work.

```sh
worktree-clean --dry-run
worktree-clean
worktree-clean --root ~/work/medulla --force
```

### `repo-remotes [--dry-run] [--root <dir>] [--quiet]`

Points every cloned TinyHumans repository at the right pair of remotes: `origin`
at the `senamakel` fork, `upstream` at the canonical `tinyhumansai` repo. It
covers both top-level clones and submodules under `<root>` (default `~/work`),
and `install.sh` runs it on every box so the layout converges everywhere.

A repository with no fork is **reported, never rewritten** — the installer does
not create repositories on your GitHub account as a side effect. Fork those
deliberately with `gh-fork-clone tinyhumansai/<name> --clone=false` and re-run.
Workflow superprojects (`workflow-*`, `*-workflow`), `medulla-v1`, and GitHub
wiki sidecars (`*.wiki`) are always skipped; wikis cannot be forked at all, and
the workflow roots coordinate shared gitlinks so they stay on upstream.

```sh
repo-remotes --dry-run
repo-remotes
```

### `atomic-commit [--json] "<scoped message>" -- <path>...`

Creates a commit from an explicit file list. It rejects directories, unchanged
paths, traversal, and implicit catch-all pathspecs; unstages unrelated work
without discarding it; and stages and commits only the named files.

```sh
atomic-commit "bin: add worktree helper" -- bin/worktree .gitignore
atomic-commit --json "docs: explain setup" -- README.md
```

### `auto-commit [--hook] [--now] [--dry-run] [--json]`

Commits whatever is dirty, with a subject written from the diff. Wired as a
`PostToolUse` hook on every tool in `claude/settings.json` and `codex/hooks.json`,
it fires on **every tool call** by default (`AUTO_COMMIT_EVERY=1`), so work is
checkpointed continuously instead of depending on an agent to remember.

That is cheaper than it sounds: a tool call that changed nothing exits at the
`git status` check without a model call, costing about 0.1s. Only calls that
actually dirty the tree pay for a commit, so the cost tracks how often files
change rather than how many tools run. Raise `AUTO_COMMIT_EVERY` to checkpoint
less often. This is why `RULES.md` no longer
carries a commit-after-every-step rule — the hook does it, and the rule was
costing context on every single turn.

The commit itself goes through `atomic-commit`, which unstages everything else
first without discarding it, so a file this command declined to touch cannot ride
along on an index left dirty by something else.

These are working checkpoints, not curated history: they take whatever is dirty
at that moment, which may span more than one concern. Expect to squash a branch
built this way. Reach for `atomic-commit` directly when a specific commit matters.

Guards, all deliberate and all tested:

- refuses on `main`/`master` unless `AUTO_COMMIT_ALLOW_PROTECTED=1`, because new
  work belongs on a feature branch and silently checkpointing onto main would
  break that several times a minute
- never stages a path that looks like a credential (`.env`, `*.pem`, `id_rsa*`,
  `*credentials*`, …) whatever `.gitignore` says, since nobody reviews these
  files before they are staged; the file is left in the working tree, not lost
- **scans the content it is about to commit**, because the commoner leak is a key
  pasted into ordinary source that no filename rule would catch. Only the lines
  this commit would *add* are checked, against high-signal shapes a provider
  issues and that cannot plausibly occur by accident — AWS, OpenAI/Anthropic,
  OpenRouter, GitHub, Slack, Google, Stripe keys, PEM private-key blocks, JWTs.
  A matching file is withheld while the rest of the commit proceeds, and in hook
  mode the command exits 2 so the harness is told which file and which pattern —
  **never the matched value**, which must not reach a log or scrollback.
  `AUTO_COMMIT_SCAN_CONTENT=0` disables it; `AUTO_COMMIT_SECRET_PATTERNS` adds
  `name|regex` pairs
- does nothing during a merge, rebase, cherry-pick, or bisect, or on a detached
  HEAD
- commits with a plain `wip:` subject when the model is unreachable — a
  checkpoint with a dull message beats a lost checkpoint
- never pushes

The subject comes from one HTTPS request to OpenRouter (~3s) carrying the stat
and truncated diff. `OPENROUTER_API_KEY` stays on the laptop, so the remote boxes
fall back to the plain subject rather than failing.

Subjects follow Conventional Commits (`type(scope): description`), followed by a
blank line and a short bulleted description of what changed — both come from the
same single model call. A reply that is not in Conventional form keeps its
description and gets `chore:`, so the log stays parseable without discarding
something that read the diff; a reply with no bullets gets a body naming the
files. `AUTO_COMMIT_BODY_MAX_LINES` (6) caps how much description is kept.

```
chore: add billing docs and discount module

- Add BILLING.md documenting billing workflows and policies
- Add discount.py with discount calculation logic
```

Latency is ~1.5-3s on the calls that fire and ~0.1s on the rest, which are a
counter increment and nothing more. Reasoning is explicitly disabled in the
request: this question does not need deliberation, and leaving it on doubled the
wait (3.3s against 1.7s measured) while consuming the token budget before any
content was emitted.

Subject generation is capped at `AUTO_COMMIT_TIMEOUT` (5s), covering connect and
transfer, and the CLI override is bounded the same way since macOS ships no
`timeout`. Past the cap it commits anyway with a static
`chore: files changed a,b,c` naming the first `AUTO_COMMIT_FALLBACK_MAX_FILES`
(5) paths and counting the rest. A subject that arrives late is worthless — the
next tool call has already raced it — so the commit always wins over the wording.

Committing is **mandatory**: there is deliberately no environment switch to turn
it off, because a kill switch gets reached for exactly when checkpoints matter
most. Disabling it takes a visible edit to `claude/settings.json` or
`codex/hooks.json`. The guards above are not opt-outs — they exist so it never
commits something it should not.

```sh
auto-commit --dry-run          # show the message and files, commit nothing
auto-commit --now              # checkpoint right now
AUTO_COMMIT_EVERY=10 …         # checkpoint every 10th tool call instead
```

### `codex-trust-hooks [--list] [--dry-run]`

Enables the shared Codex hooks on this machine. Codex records every hook it
discovers in `~/.codex/config.toml` with a `trusted_hash` and an `enabled` flag
that **defaults to false** — so a hook does nothing until something flips it.
Normally that is an interactive prompt, which never appears on a headless box
and will block `codex exec` waiting for an answer it cannot show.

`codex/hooks.json` is shared through this repo, so every machine computes the
same `trusted_hash`; only the enable flag is machine-local, which is why it
cannot simply be synced. Run this once per box, and again whenever
`codex/hooks.json` changes, since editing it invalidates the recorded hash.

Only entries pointing at this repo's `hooks.json` are touched; anything else
Codex has registered is left alone, and the config is backed up first.

```sh
codex-trust-hooks --list      # show which hooks are enabled
codex-trust-hooks             # enable the repo's hooks
```

### `tune-box [--dry-run] [--clean-targets] [--report]`

Applies build, memory, and I/O tuning appropriate to the machine it runs on.
Every value is derived from that box's own cores and RAM rather than hardcoded,
because these machines differ by roughly 3x in both. Re-running is safe:
existing settings are reported and left alone, never duplicated or overwritten,
so anything tuned by hand survives.

Everywhere it installs `sccache` and points cargo at it — the worktrees of a
superproject otherwise each compile an identical dependency graph — caps cargo
parallelism from **RAM rather than core count** (rustc wants gigabytes per job,
and a core it cannot feed is worse than an idle one), drops debug info for
dependencies, and disables incremental compilation, which writes thousands of
small files per crate and cannot be cached by sccache.

On Linux it additionally configures **zram** (compressed swap in RAM, so
swapping costs CPU instead of disk I/O), raises `vm.swappiness` to suit it, caps
the systemd user slice with `MemoryHigh`/`AllowedCPUs` so a runaway test suite
degrades throughput instead of taking the box down, and sets **fstrim to daily**
— a weekly TRIM is far too rare for checkouts that create and delete
multi-gigabyte `target/` dirs; on one box a six-day backlog cost 40x random-read
throughput and left p99 latency at 759 ms.

macOS deliberately gets none of those four: it compresses memory natively, has
no swappiness knob, and APFS issues TRIM itself.

`MemoryHigh` is used rather than `MemoryMax` on purpose — the former throttles
and reclaims, the latter kills, and this fleet has already had systemd-oomd
killing tmux panes once.

```sh
tune-box --dry-run        # show what would change
tune-box                  # apply
tune-box --clean-targets  # also delete stale cargo target dirs
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

### `pr-comments [<number>] [--json] [--all] [--threads-only] [--from <login>]...`

Lists the review feedback on a pull request, defaulting to the PR for the
current branch. GitHub splits feedback across three channels and review bots
use all of them, so the report covers each one: inline **threads** (the only
resolvable kind, each carrying the `threadId` that `pr-reply` needs),
review-level **reviews** (where `greptile-apps` and `chatgpt-codex-connector`
post their findings, each carrying the `reviewId` that `pr-review-resolve`
needs), and top-level **comments** (where `coderabbitai` posts its summary).
Reading only inline threads silently drops most bot feedback.

Unresolved threads are listed by default; outdated ones are kept because their
feedback usually still applies. A `CHANGES_REQUESTED` review is reported as
`blocking` only while it is that reviewer's latest verdict — a later approval
or dismissal supersedes it. `--all` adds resolved threads and superseded
reviews, `--threads-only` narrows to the resolvable threads, and `--from`
filters every section by author. `--json` emits full comment bodies.

```sh
pr-comments
pr-comments 123 --json
pr-comments 123 --from coderabbitai
pr-comments 123 --threads-only
```

### `pr-reply <threadId> (--body <text> | --body-file <path>) [--no-resolve]`

Replies in a review thread and resolves it — the normal way to close out a
review comment: answer it, then mark it done. `threadId` is the `PRRT_…`
identifier from `pr-comments`; it is globally unique, so no repository argument
is needed. `--no-resolve` replies and leaves the thread open (use when the reply
asks the reviewer a question), `--resolve-only` resolves without replying, and
`--unresolve` reopens a thread. Empty reply bodies are rejected. `--dry-run`
prints the mutations without sending them.

```sh
pr-reply PRRT_kwDO… --body "Fixed in 48b0341 — the guard now covers the detached path."
pr-reply PRRT_kwDO… --body-file reply.md --no-resolve
pr-reply PRRT_kwDO… --resolve-only
```

### `pr-review-resolve [<number>] (--list | --approve | --dismiss <reviewId> | --dismiss-all | --re-request)`

Clears the changes-requested verdicts blocking a PR. `--list` reports which
reviews still block (the same set `pr-comments` counts). After pushing a fix,
`--re-request` asks those reviewers to re-review — the preferred way to clear a
verdict. `--dismiss` retires one review and `--dismiss-all` every blocking one;
both require a `--message` explaining why and repository write access, and both
are a last resort. `--approve` submits an approving review, which is how a
reviewer clears their own verdict; GitHub rejects approving your own PR.
`--dry-run` shows the effect without applying it.

```sh
pr-review-resolve 123 --list
pr-review-resolve 123 --re-request
pr-review-resolve 123 --dismiss-all --message "Addressed in 48b0341; see thread replies."
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
to the contributor's fork so `git push` updates the PR, initializes submodules
with `submodule-init` (shallow, full-depth fallback), then launches the chosen
harness (default `claude`) with a fix-the-PR prompt plus any extra text. When
the harness exits you're asked whether to delete the worktree.
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

### Langfuse helpers (`langfuse-env`, `langfuse-sessions`, `langfuse-session`, `langfuse-traces`, `langfuse-trace`, `langfuse-transcript`, `langfuse-observation`)

Read-only tools that pull Langfuse sessions, traces and transcripts into a shape
an agent can work with, for the staging and production instances and for the
OpenHuman and Medulla workloads. The `langfuse` MCP server covers prompts,
datasets, scores and evaluators but exposes **no** session/trace/observation
reads — that gap is what these fill, by calling the Langfuse public API
(`/api/public/*`) directly. All share `bin/langfuse-lib.sh` and take `--json` for
structured output.

**Environments** (`--env <alias>`) select the Langfuse instance and key pair, and
therefore staging vs production. The map lives at `~/.config/langfuse/envs.tsv`
(override `LANGFUSE_ENVS`), one `alias<TAB>base-url<TAB>public-key<TAB>secret-key`
per line. A public-key field of `@/path/to/file` instead reads
`LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY` (and `LANGFUSE_BASE_URL`, when
base-url is `-`) out of that JSON or dotenv file, so an env can point straight at
the deployment secrets it already has and no key is copied to a second place.
Resolution order: `--env` → `LANGFUSE_PUBLIC_KEY`/`LANGFUSE_SECRET_KEY` in the
environment → `LANGFUSE_ENV` → the `default` alias (or the only entry).

**Projects** (`--project <alias>`) are *not* credentials. One Langfuse project
holds every workload for an environment — on staging, Medulla's `medulla-session`
traces sit beside OpenHuman's `agent.turn` and `flow.run:*` — so "which product
is this" is a trace-name question. `~/.config/langfuse/projects.tsv` (override
`LANGFUSE_PROJECTS`) maps `alias<TAB>trace-name-regex`; with no map entry the
alias is used as the regex. The regex is matched after fetching (the API's own
`name` filter is exact-match only, and one product emits several names), so
`--project` over-fetches to still satisfy `--limit`. Use `--name` for an exact,
server-side filter.

- `langfuse-env [--list] [--json]` — resolve and verify environments. Each is
  probed with `GET /projects`, which reports the Langfuse project and org a key
  pair really belongs to — the reliable way to tell two envs on one host apart.
  Secret keys are never printed. Also lists the configured project presets.
- `langfuse-sessions [--project <a>] [--since 24h] [--environment <e>] [--user <id>] [--limit N]`
  — recent sessions. With `--project`/`--user` the list is derived from matching
  traces (sessions themselves carry no name or user), and then also reports each
  session's trace count, names, user and cost.
- `langfuse-session <session-id>` — one session's metadata and the traces in it,
  in one API call and with no observation payloads. The cheap overview.
- `langfuse-traces [--project <a>] [--name <exact>] [--session <id>] [--user <id>] [--tag <t>] [--since 24h] [--limit N]`
  — traces with timing, cost, tags, observation counts and clipped input/output.
- `langfuse-trace <trace-id> [--type GENERATION] [--io] [--max-chars N]` — one
  trace's observation tree with model, latency, tokens and cost per step;
  `--io` prints full payloads instead of previews.
- `langfuse-transcript <session-id|trace-id> [--full] [--max-chars N] [--max-traces N] [--max-steps N]`
  — the readable conversation: each trace's user input and final output, plus a
  one-line summary of the steps between. `--full` adds every generation's
  messages, system prompts included — what you want when debugging what the
  model actually saw. The id may be either kind: sessions are tried first and a
  404 falls back to a trace, since the two look alike in the Langfuse UI. One
  agent turn can carry thousands of observations (an OpenHuman `agent.turn`
  routinely exceeds 10k), so steps are capped at `--max-steps` (default 40) and
  the tool reports how many it left out; `--full` counts generations only.
- `langfuse-observation <id> | --list [--trace <id>] [--type GENERATION] [--name <n>] [--since 24h]`
  — the drill-down once a transcript points at one model call: untruncated
  messages, output, model parameters, tokens and cost.

Payloads are clipped per field with a visible `…[+N more chars]` marker, so an
agent can always tell truncated data from complete data and re-fetch with a
larger `--max-chars` (`0` disables clipping on `langfuse-observation`). Every
cap — traces, steps, page size — reports what it dropped rather than silently
truncating. What a transcript can show still depends on what the service logged:
Medulla's `medulla-session` traces carry full prompts and replies, while
OpenHuman's `agent.turn` model spans currently record structure and token counts
but no input/output.

```sh
langfuse-env --list                                   # which envs work, and what they point at
langfuse-sessions --env staging --project medulla --since 24h
langfuse-transcript 35cdf638-… --env staging          # read the conversation
langfuse-transcript 35cdf638-… --env staging --full   # with every prompt the model saw
langfuse-traces --env prod --project oh --since 7d --json
langfuse-observation 5cd9db98… --env staging          # one model call, in full
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

### `ocr [args...]`

Runs Alibaba's OpenCodeReview CLI through OpenRouter using the same machine-local
`OPENROUTER_API_KEY` as `deepcode`. Install and configure the npm package with
`install-open-code-review`; the installer stores only the OpenRouter URL, protocol,
and DeepSeek model names in `~/.opencodereview/config.json`, never the key. Reviews
default to `deepseek/deepseek-v4-pro`; `deepseek/deepseek-v4-flash` is also
configured and can be selected with OCR's `--model` option.

```sh
install-open-code-review
ocr llm test
ocr review
ocr review --from main --to feature-branch
```

### `workflow-update [--no-commit]`

Selects `upstream/main` for each first-level submodule when available, falling
back to `origin/main`. Each submodule is forced onto local `main` at the selected
commit, discarding divergent local commits and tracked changes while leaving
untracked files untouched. The superproject itself is not fetched, merged,
switched, or reset. Changed submodule pointers are staged and committed as
"Update submodule pointers"; `--no-commit` stages them without committing.

Moving a submodule to a new commit moves the nested gitlinks it records, so each
updated submodule is then re-initialized **recursively** through `submodule-init`
— otherwise the checkout silently keeps the vendored sources the *previous*
commit named. Only `refs/heads/main` is fetched, which keeps the fetch
proportional to the branch rather than the whole repository, and fetches run with
terminal and SSH prompts disabled so a missing credential fails instead of
hanging forever on input no agent will supply.

## Notes

- The `humanizer` skill was originally managed by the `~/.agents` skill
  manager (see its `.skill-lock.json`). It is vendored here as a plain copy,
  so update it by re-copying from upstream and rerunning `bin/check-skills`.
- `worktree/` and `worktrees/` are gitignored — feature branches may live in
  either convention without polluting repository status.
- The `langfuse-*` and `sentry-*` maps (`~/.config/langfuse/envs.tsv`,
  `~/.config/langfuse/projects.tsv`, `~/.config/sentry/repos.tsv`) are
  machine-local and deliberately not synced: they name credentials and local
  secret paths. Credentials stay on the primary laptop and are not copied to the
  remote boxes, so these tools are expected to be unconfigured there — that is
  the intended state, not a broken install. `sync.sh` distributes code and
  rules only.
