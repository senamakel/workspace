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
| `zsh/zshrc` | `~/.zshrc` |
| `zsh/zshenv` | `~/.zshenv` |

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

## Notes

- The `humanizer` and `solana-dev` skills were originally managed by the
  `~/.agents` skill manager (see its `.skill-lock.json`); they are vendored
  here as plain copies, so update them by re-copying from upstream.
- `worktrees/` is gitignored — feature branches live there as git worktrees.
