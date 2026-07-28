# Repository Guidelines

## Project Structure & Module Organization

This repository is the source of truth for personal shell and coding-agent configuration. `install.sh` links managed files into the user’s home directory. Shared workflow rules live in `RULES.md`; shared agent sources live in `agents/<name>/` and are rendered into harness-native files. Shared skills live in `skills/<name>/` and are linked into both Claude and Codex. Other harness-specific configuration is under `claude/`, `codex/`, and `opencode/`. Executable helpers belong in `bin/`, while custom shell aliases and functions live in `zshrc`. Keep every skill self-contained, with `SKILL.md` as its entry point and optional resources inside the same directory.

Do not commit machine-local credentials or generated state. In particular, `~/.codex/config.toml` and the local OpenCode package/config files are intentionally excluded.

## Build, Test, and Development Commands

There is no compilation step or centralized test suite. Validate the part you change:

- `./install.sh --dry-run` previews symlink and loader changes without modifying home-directory files.
- `bin/check-skills` validates every canonical skill’s directory and frontmatter.
- `bin/check-open-source-state` validates the shared repository catalog and
  contribution queue.
- `tests/open-source-state.sh` and `tests/open-source-agent.sh` exercise the
  open-source pipeline state and launcher.
- `tests/worktree-clean.sh` exercises worktree reclamation against a throwaway
  repository with dirty, unpushed, and submodule-bearing worktrees.
- `bash -n install.sh bin/* claude/statusline-command.sh` checks Bash syntax.
- `zsh -n zshrc` checks the sourced Zsh configuration.
- `git diff --check` catches whitespace errors before committing.

Run `./install.sh` only from the primary checkout, because links created from a disposable worktree will break when that worktree is removed.

## Syncing Remote Workspaces

After changes have landed on `origin/main`, update all three remote boxes from
their primary checkouts. Preserve any machine-local tracked changes; investigate
a failed fast-forward instead of resetting or stashing them automatically.

```sh
ssh enamakel@dragonfly 'cd ~/work/workspace && git pull --ff-only && ./install.sh'
ssh enamakel@mac-mini 'cd ~/work/workspace && git pull --ff-only && ./install.sh'
ssh droid@robot1.digital.ocean 'cd ~/work/workspace && git pull --ff-only && ./install.sh'
```

Use a login-capable remote shell if a host's non-interactive `PATH` cannot find
standard tools. Confirm each pull and install succeeds before reporting the
three machines as synchronized.

## Coding Style & Naming Conventions

Shell scripts use `#!/usr/bin/env bash`, two-space indentation, quoted variable expansions, and defensive settings such as `set -euo pipefail` where appropriate. Prefer small functions with clear lowercase names and local variables. Name command-line tools with lowercase kebab-case (`workflow-update`) and skill directories after the capability they provide. Keep JSON/JSONC formatting consistent with neighboring files.

## Testing Guidelines

For installer changes, exercise both dry-run behavior and idempotency; a second run should report existing links without replacing them. For CLI helpers, test argument validation and the safest non-mutating path available. Document any manual verification in the pull request.

## Commit & Pull Request Guidelines

Recent history favors short, scoped, imperative subjects such as `bin: add deepcode wrapper` and `readme: document the deepcode tool`. This repository is the exception to the shared worktree workflow: do not create or use worktrees for workspace-repo changes. Work in the primary checkout on a feature branch instead. Commit with `atomic-commit "<scoped message>" -- <explicit files...>` so unrelated changes remain uncommitted. Describe behavior and validation in the PR, and link relevant issues. Screenshots are only needed for user-visible terminal or status-line changes. Open PRs against the canonical upstream repository, not a personal fork.

Operational updates under `open-source/` are the narrow exception to the PR
rule: agents may commit and push one validated state file directly to `main` so
other machines can claim work safely. They must pull with rebase before and
after the state edit, never force-push, and abandon a claim if the same issue
record conflicts.
