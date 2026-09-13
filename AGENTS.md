# Repository Guidelines

## Project Structure & Module Organization

This repository is the source of truth for personal shell and coding-agent configuration. `install.sh` links managed files into the user’s home directory. Shared workflow rules live in `RULES.md`; shared agent sources live in `agents/<name>/` and are rendered into harness-native files. Shared skills live in `skills/<name>/` and are linked into both Claude and Codex. Shared Medulla workflow definitions live in `workflows/<name>.json`, and the whole directory is symlinked over `~/.medulla/<account id>/workflows/` — for the active account named by `~/.medulla/active_user.toml` and any other account already on the machine. It is the directory, not each file: Medulla saves a flow by renaming a temporary file over the target, which replaces a per-file symlink with a regular file, so flows edited or created in Medulla never reached this repository. With the directory linked, the rename lands inside `workflows/` and every flow Medulla writes is a change in this checkout. Medulla scopes its workflow store per account, so the flat `~/.medulla/workflows/` is *not* read; `install.sh` removes the links it used to leave there. The portable half of Medulla's own settings lives in `medulla/config.toml` and is merged into each account's live `config.toml` by `bin/medulla-config-merge` — whole sections at a time, leaving `[fleet]`, `[harness]` and `[backend]` as that machine wrote them. It is merged rather than linked for the same rename reason. Hooks shared across harnesses belong in that file's `[[hooks]]` array rather than in `claude/settings.json`, so one declaration reaches every harness Medulla launches. Harness presets belong in its `[[customHarnesses]]` array for the same reason the flows are linked: a workflow names a harness by id, so a flow that reaches every box while the preset it dispatches to exists on only one still fails at dispatch with `custom harness "…" is not configured on this host`. Every preset sets `hostId = "this-device"` — Medulla's own default host id — so the one block is correct everywhere. A preset added through Medulla's UI survives until the next `./install.sh`; add it here instead. Shared git settings live in `gitconfig` and are pulled into `~/.gitconfig` with `include.path` rather than replacing it, so machine-local values (signing key, GPG path, credential helpers) stay put. Other harness-specific configuration is under `claude/`, `codex/`, and `opencode/`. Executable helpers belong in `bin/`, while custom shell aliases and functions live in `zshrc`. Keep every skill self-contained, with `SKILL.md` as its entry point and optional resources inside the same directory.

Do not commit machine-local credentials or generated state. In particular, `~/.codex/config.toml` and the local OpenCode package/config files are intentionally excluded, as are the credential maps the `bin/` helpers read (`~/.config/langfuse/envs.tsv`, `~/.config/langfuse/projects.tsv`, `~/.config/sentry/repos.tsv`). Tools may point at existing secret files by path, but must never copy a key into this repository.

## Build, Test, and Development Commands

There is no compilation step or centralized test suite. Validate the part you change:

- `./install.sh --dry-run` previews symlink and loader changes without modifying home-directory files.
- `bin/check-skills` validates every canonical skill’s directory and frontmatter.
- `bin/check-open-source-state` validates the shared repository catalog and
  contribution queue.
- `bin/ladder-up --check` reports whether this box's LLM router container is
  running and what it would change, without touching it.
- `bin/cortex-up --check` does the same for this box's CortexDB and its Tika
  sidecar.
- `tests/open-source-state.sh` and `tests/open-source-agent.sh` exercise the
  open-source pipeline state and launcher.
- `tests/worktree-clean.sh` exercises worktree reclamation against a throwaway
  repository with dirty, unpushed, and submodule-bearing worktrees.
- `tests/auto-commit.sh` exercises the auto-commit hook's offline logic — the
  tool-call counter, the repository allowlist, the detached-HEAD and
  in-progress-operation guards, the per-repository lock that keeps two
  overlapping runs off one index, credential filtering, the subject fallback,
  and the refusal log — with a stubbed model and no credentials.
- `tests/langfuse-lib.sh` exercises the Langfuse helpers' offline logic —
  environment resolution, project presets, time windows, and paging — with a
  stubbed API and no credentials.
- `bash -n install.sh bin/* claude/statusline-command.sh` checks Bash syntax.
- `zsh -n zshrc` checks the sourced Zsh configuration.
- `git diff --check` catches whitespace errors before committing.

Run `./install.sh` only from the primary checkout, because links created from a disposable worktree will break when that worktree is removed.

## The LLM Router

Every box runs its own `llm-ladder-router` container on `127.0.0.1:6969`, and
Medulla's shared `ladder` harness preset plus the PR-babysitting workflows
dispatch to it. Nothing about it is meant to be reachable from the tailnet; a
box routes only for itself.

`bin/ladder-up` is what keeps it up. It is idempotent and cron-safe: a healthy
container is left alone, a stopped one is started, and one whose run arguments
no longer match — a changed port, memory cap, key set, or image — is recreated.
It finishes by asking the router for a real answer, because a container in
`running` that is wedged is not up. Use `--recreate` after exporting a new key,
since docker copies the environment in at create time and a running container
never sees a later one, and `--pull` to move to a new image.

### The config is this repository's, not the box's

`ladder/config.toml` is the fleet's router config, and `ladder-up` installs it
to `~/.config/ladder/config.toml` whenever the two differ, backing up what it
replaces. That is what makes the ladders the same on every box: before this,
each box's config was hand-edited and drifted, and the only way to find out how
was to read three files.

It holds **no secret** — every credential is named as an environment variable,
which is what lets one file be the config everywhere. The keys themselves stay
in `~/.zshenv` on each box and never enter this repository, which is public.

A config is installed only once the image about to run it has accepted it,
checked with `docker run --rm <image> --config <candidate> --check`. The two
move together and the config usually moves first, so this ordering is the whole
point: a config the running binary cannot parse is not a degraded router, it is
no router. The container exits at startup, `--restart always` restarts it into
the same failure, and the box crash-loops until a person looks. That is not
hypothetical — a config carrying `aliases` did exactly this to dragonfly
against an image that predated them, and the five-minute watchdog turned one
bad config into a restart loop rather than catching it.

When validation fails the box keeps the config it has and says so:

```
ladder-up: repository config is not valid for <image>; keeping <config>
ladder-up: this box is probably behind; try: ladder-up --pull
```

which is nearly always a box running an image older than the config. So after a
router release, spread it with the image first:

```sh
./sync.sh                       # get the new config onto every box
box <name> -- ladder-up --pull  # then move each box to the new image
```

`--pull` refreshes the image and *then* validates, so a single `--pull` run on
a stale box picks up both halves in the right order.

Each box runs it every five minutes, which is what makes the router survive the
ways it actually dies. Docker's own `--restart always` is not enough: it covers
a crashed process and a rebooted daemon, but a container stopped or killed by
hand stays down until something starts it, and dragonfly's sat exited for three
hours after a cgroup OOM kill took it out alongside a `lean` process. The
watchdog is the guarantee; the restart policy is the fast path.

Three of the boxes run it from cron:

```cron
PATH=/usr/local/bin:/usr/bin:/bin
*/5 * * * * $HOME/work/workspace/bin/ladder-up --quiet >> $HOME/.cache/ladder-up.log 2>&1
```

Use an absolute path: cron runs from `$HOME` with almost no environment, which
is also why the script finds `docker` itself and reads the marketplace keys out
of `~/.zshenv` rather than expecting a profile. It reads them by sourcing that
file with `zsh`, not by parsing it — robot1 defines `LADDER_API_KEY` as a
command substitution over the router's own config, and a line-parser hands the
container the literal `$(sed ...)`. Those keys stay in `~/.zshenv` on each box
and never in this repository, which is public.

mac-mini is the exception: `crontab` there fails with `Operation not permitted`
over ssh, because macOS withholds the access it needs from a non-interactive
session. It runs the same command from a launchd agent instead,
`~/Library/LaunchAgents/ai.tinyhumans.ladder-up.plist`, with `StartInterval`
300 and `RunAtLoad`. Check it with
`launchctl print gui/$(id -u)/ai.tinyhumans.ladder-up`.

## The Memory Store

Every box also runs its own CortexDB on `127.0.0.1:3141`, the ladder's twin:
one shared corpus per box that any agent landing there can capture into and
recall from without setting a store up first. `bin/cortex-up` keeps it up the
way `ladder-up` keeps the router up — idempotent, cron-safe, `--check`,
`--pull`, `--recreate`, and a real authenticated probe at the end — and runs
Apache Tika beside it as `cortex-tika` on a private docker network, because
that is the only shape CortexDB accepts for parsing PDF and DOCX.

### Every feature is on, and the config is this repository's

`cortex/cortex.env` is the fleet's store config, passed to `docker run
--env-file`. A fresh CortexDB is deliberately vector-only — no entity graph, no
facts, no enrichment, no episodes or beliefs, no artifacts, no code plane, no
documents — and every layer beyond that is its own opt-in switch. The env file
turns on every one the fleet can serve: enrichment on a 60s WAL scan, the
synthesis scheduler, the entity graph with grounding and multi-hop joins,
bitemporal facts in `enforce`, the artifact pipeline, the code plane, Tika
documents, and `/v1/answer` with its verifier. The one it cannot is the
cross-encoder reranker, which needs Cohere or a local model the image does not
ship; `cortex-up` switches it on when `COHERE_API_KEY` is exported on a box.

Every model call the store makes goes through the box's own ladder — `vectors`
for embeddings, `flash` for extraction and enrichment, `reasoning` for the
answer writer and verifier — so there is one egress path and one set of
provider keys, and the names mean the same on every box because
`ladder/config.toml` is the same file everywhere. That also means the store is
only as up as the ladder: `cortex-up` fails when `/v1/admin/ready` reports
`degraded: true`, and says which check.

The env file holds **no secret**. `cortex-up` adds the keys from `~/.zshenv`:
`LADDER_API_KEY` (required, and passed under every name the binary reads for
the embedding, entity, enrichment, answer and verifier lanes — including the
generic `OPENAI_API_KEY`/`LLM_API_KEY`, without which v0.9.9 does not fail but
silently falls back to mock embeddings and pins the volume to them),
`CORTEX_API_KEY` (the bearer callers present; generated once into
`~/.config/cortex/api-key` if `~/.zshenv` has none), and `COHERE_API_KEY`
(optional). Docker copies the environment in at create time, so a changed key
needs `--recreate`; a changed env file does not, because its contents are part
of the container's spec hash and the next run recreates on its own.

### The corpus is the volume

Data lives in the named docker volume `cortex-data`, which `cortex-up` never
removes. The embedding width — 1024, what the ladder's `vectors` returns — and
the provider are pinned on first ingest and rejected forever after, so "which
volume" is the same question as "which corpus". A store that ever started
without a usable ladder key is pinned to `mock::1024` for good; `cortex-up`
refuses that state and prints the `docker volume rm` that starts over, which
is only correct while the volume holds nothing worth keeping.

To use it from a shell on the box:

```sh
export CORTEX_URL=http://127.0.0.1:3141
export CORTEX_API_KEY="$(cat ~/.config/cortex/api-key)"   # or from ~/.zshenv
curl -s "$CORTEX_URL/v1/admin/ready"                       # public
curl -s -X POST "$CORTEX_URL/v1/recall" -H "Authorization: Bearer $CORTEX_API_KEY" \
  -H 'content-type: application/json' -d '{"scope":"ws:demo","query":"..."}'
```

From a container on the box, `http://host.docker.internal:3141` on Docker
Desktop, and the docker0 address on Linux, where the port is also published.

### Keeping it up

The same watchdog as the router, in the same cron line on the Linux boxes:

```cron
*/5 * * * * $HOME/work/workspace/bin/cortex-up --quiet >> $HOME/.cache/cortex-up.log 2>&1
```

and on mac-mini a launchd agent,
`~/Library/LaunchAgents/ai.tinyhumans.cortex-up.plist`, `StartInterval` 300
and `RunAtLoad`. `cortex-up --pull` moves a box to a new CortexDB or Tika
image; run it after `./sync.sh` when `cortex/cortex.env` starts using a switch
the running image does not know.

One networking detail worth knowing, because its failure is silent. The store
reaches the ladder as `host.docker.internal`. On Linux `cortex-up` adds that
name as the docker0 IPv4 the router binds on. On Docker Desktop it adds
nothing, because Desktop's DNS already resolves the name to one working IPv4
and `--add-host host.docker.internal:host-gateway` there adds an IPv6 entry
beside it that does not route — `curl` shrugs and uses the v4, the store's
HTTP client does not, and every embedding call fails with a bare "error
sending request" while the rows sit "kept for retry".

## Syncing Remote Workspaces

After changes have landed on `origin/main`, update all three remote boxes from
their primary checkouts. Preserve any machine-local tracked changes; investigate
a failed fast-forward instead of resetting or stashing them automatically.

```sh
./sync.sh            # all boxes: push if ahead, pull --rebase, ./install.sh
./sync.sh --check    # report each box's HEAD and dirty files, change nothing
./sync.sh dragonfly  # one box
```

`sync.sh` runs the remote commands through a login shell, because the
non-interactive `PATH` on some boxes cannot find tools `install.sh` requires
(`rg`). It pulls with `--rebase` and autostash so machine-local tracked edits
survive; a genuine conflict still stops that box and is reported.

Use a login-capable remote shell if a host's non-interactive `PATH` cannot find
standard tools. Confirm each pull and install succeeds before reporting the
three machines as synchronized.

## Coding Style & Naming Conventions

Shell scripts use `#!/usr/bin/env bash`, two-space indentation, quoted variable expansions, and defensive settings such as `set -euo pipefail` where appropriate. Prefer small functions with clear lowercase names and local variables. Name command-line tools with lowercase kebab-case (`workflow-update`) and skill directories after the capability they provide. Keep JSON/JSONC formatting consistent with neighboring files.

## Testing Guidelines

For installer changes, exercise both dry-run behavior and idempotency; a second run should report existing links without replacing them. For CLI helpers, test argument validation and the safest non-mutating path available. Document any manual verification in the pull request.

## Commit Guidelines

Commit subjects follow Conventional Commits — `type(scope): description`, with
`feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`,
`style`, or `revert`. The `auto-commit` hook writes them in that form, so
hand-written commits should match.

**This repository does not use pull requests.** Commit and push straight to
`main`; do not open a PR, and do not create a feature branch for it. This is a
personal configuration repo with a single author, where a PR adds a review round
trip with no reviewer on the other end. Pull with rebase before pushing, never
force-push, and keep each commit scoped with
`atomic-commit "<scoped message>" -- <explicit files...>` when it needs a
deliberate scope. Everything else in `RULES.md` about raising PRs upstream still
applies to every *other* repository.

Do not create or use worktrees for workspace-repo changes; work in the primary
checkout. Validate the part you changed before pushing, and say what you ran in
the commit message. Screenshots are only needed for user-visible terminal or
status-line changes.

Operational updates under `open-source/` follow the same direct-to-`main` rule,
with one extra requirement: agents must pull with rebase before and after the
state edit and abandon a claim if the same issue record conflicts, so two
machines cannot claim the same work.
