# workspace

Personal dotfiles / agent config. `install.sh` symlinks most files into `$HOME`
and builds shared agent sources into native harness formats. This repo remains
the source of truth, so source changes appear in `git diff`.

## Layout

| Repo path | Installed to |
|---|---|
| `rules.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.codex/CODEX.md`, `~/.config/opencode/AGENTS.md` (one shared rules file, linked into every agent) |
| `agents/<name>/` | Canonical agent metadata and instructions; `install.sh` builds both harness formats |
| `claude/settings.json` | `~/.claude/settings.json` (hooks, statusline, plugins) |
| `claude/mcp.json` | `~/.claude/mcp.json` |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` |
| `claude/skills/<name>/` | `~/.claude/skills/<name>` (one link per skill dir) |
| `bin/*` | on PATH via the repo `zshrc` (no symlinks) |
| `codex/hooks.json` | `~/.codex/hooks.json` |
| `codex/skills/<name>/` | `~/.codex/skills/<name>` (one link per skill dir) |
| `zshrc` | sourced from `~/.zshrc` via an appended loader line |

`rules.md` is the single source of truth for agent instructions: it is
symlinked into each agent's own instructions file (Claude's `CLAUDE.md`,
Codex's `AGENTS.md`/`CODEX.md`, opencode's `AGENTS.md`), so all three always
share the same rules. Edit `rules.md` and the change is live for every agent
(re-run `install.sh` only if a link is missing).

`agents/` is the single source of truth for reusable subagents. Do not edit the
generated cache or installed harness files; edit `agent.json` or
`instructions.md`, then re-run `install.sh`.

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
- New skill: add a directory with a `SKILL.md` under `claude/skills/`,
  re-run `./install.sh`.
- New slash command: create `claude/commands/`, add it to `install.sh` the
  same way agents are handled, and re-run.

## Tools

### `pr-list [--json] [--limit <count>] [-R|--repo <owner/name>]`

Lists open pull requests for the current repository, preferring its
`upstream` remote over `origin`. The concise default report includes each
PR's title, shortened body, review state, CI summary, branches, and
mergeability (`can_merge`, `has_conflicts`, `blocked`, `behind_base`, or
`unstable`). Use `--json` for stable, structured agent input, or `--repo` to
inspect another repository from any directory.

```sh
pr-list
pr-list --json
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
`PR_FIX_SAFE=1` disables the yolo/bypass flags; `PR_FIX_REPO` overrides repo
resolution. Conventions follow `tinyhumansai/openhuman/scripts/shortcuts`.

Harnesses live in a small registry near the top of `bin/pr-fix`
(`HARNESSES` + `harness_launch`); adding another is a one-line name plus a
launch branch. Bypass flags per harness: `claude
--dangerously-skip-permissions`, `codex
--dangerously-bypass-approvals-and-sandbox`, `opencode --auto`.

### `deepcode [claude args...]`

Runs the Claude Code CLI but backed by DeepSeek models through OpenRouter's
Anthropic-compatible endpoint (`https://openrouter.ai/api`). It sets the
`ANTHROPIC_*` routing/model env vars in the wrapper process only and `exec`s
`claude`, so your normal `claude` (pointed at Anthropic) is unaffected. Heavy
tiers (opus/sonnet) map to `deepseek/deepseek-v4-pro`, fast/subagent tiers to
`deepseek/deepseek-v4-flash`; override with `DEEPCODE_MODEL` /
`DEEPCODE_FAST_MODEL`. Requires `OPENROUTER_API_KEY` in the environment (set
it in your `~/.zshrc`, not this repo). All arguments pass straight through to
`claude`.

### `workflow-update [--no-commit]`

For workflow superprojects (repos with submodules). Fetches the canonical
remote (`upstream` preferred, else `origin`) and merges its default branch,
then bumps each first-level submodule (no recursion) to the tip of its own
canonical remote's default branch, stages the moved pointers, and commits
them as "Update submodule pointers". `--no-commit` stages only.

## Notes

- The `humanizer` and `solana-dev` skills were originally managed by the
  `~/.agents` skill manager (see its `.skill-lock.json`); they are vendored
  here as plain copies, so update them by re-copying from upstream.
- `worktrees/` is gitignored — feature branches live there as git worktrees.
