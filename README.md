# workspace

Personal dotfiles / agent config. Everything here is installed into `$HOME`
as symlinks by `install.sh`, so this repo is the source of truth and
`git diff` shows config drift.

## Layout

| Repo path | Installed to |
|---|---|
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` (global Claude Code instructions) |
| `claude/settings.json` | `~/.claude/settings.json` (hooks, statusline, plugins) |
| `claude/mcp.json` | `~/.claude/mcp.json` |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` |
| `claude/agents/*.md` | `~/.claude/agents/<name>.md` (one link per file) |
| `claude/skills/<name>/` | `~/.claude/skills/<name>` (one link per skill dir) |
| `bin/*` | on PATH via the repo `zshrc` (no symlinks) |
| `codex/AGENTS.md` | `~/.codex/AGENTS.md` |
| `codex/CODEX.md` | `~/.codex/CODEX.md` |
| `codex/hooks.json` | `~/.codex/hooks.json` |
| `codex/skills/<name>/` | `~/.codex/skills/<name>` (one link per skill dir) |
| `zshrc` | sourced from `~/.zshrc` via an appended loader line |

`zshrc` holds only custom functions and aliases. `~/.zshrc` and `~/.zshenv`
remain local machine-specific files (oh-my-zsh setup, PATH exports, tool
installer snippets); `install.sh` keeps a marker-guarded `source` line in
`~/.zshrc` pointing at the repo `zshrc`.

`~/.codex/config.toml` is deliberately not synced: it mixes machine state
(project trust list, marketplace caches, desktop theme) with at least one
embedded API key, which must not be committed.

## Install

```sh
./install.sh --dry-run   # preview
./install.sh             # apply
```

The script is idempotent and non-interactive. Anything it replaces is moved
to `~/.config-backups/workspace-<timestamp>/` first. Run it from the primary
checkout (not a `worktrees/` checkout) so links survive worktree cleanup.

## Adding things

- New agent: drop a `.md` file in `claude/agents/`, re-run `./install.sh`.
- New skill: add a directory with a `SKILL.md` under `claude/skills/`,
  re-run `./install.sh`.
- New slash command: create `claude/commands/`, add it to `install.sh` the
  same way agents are handled, and re-run.

## Tools

### `pr-fix <pr-number> [extra prompt text...] [claude|codex]`

Checks a PR out into `<repo>/worktrees/pr-<n>` (preferring the `upstream`
remote, i.e. the canonical `tinyhumansai/*` repo), merges the base branch in
(conflicts are left for the agent), wires upstream tracking + `pushRemote`
to the contributor's fork so `git push` updates the PR, then launches the
chosen agent (default `claude`) with a fix-the-PR prompt plus any extra text.
When the agent exits you're asked whether to delete the worktree.
`PR_FIX_SAFE=1` disables the yolo/bypass agent flags; `PR_FIX_REPO`
overrides repo resolution. Conventions follow
`tinyhumansai/openhuman/scripts/shortcuts`.

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
