# Repository Guidelines

## Project Structure & Module Organization

This repository is the source of truth for personal shell and coding-agent configuration. `install.sh` links managed files into the user’s home directory. Shared workflow rules live in `RULES.md`; shared agent sources live in `agents/<name>/` and `install.sh` renders them into a user-level generated cache for Claude and Codex. Other harness-specific configuration is under `claude/`, `codex/`, and `opencode/`. Executable helpers belong in `bin/`, while custom shell aliases and functions live in `zshrc`. Keep each skill self-contained in `<agent>/skills/<skill-name>/`, with `SKILL.md` as its entry point.

Do not commit machine-local credentials or generated state. In particular, `~/.codex/config.toml` and the local OpenCode package/config files are intentionally excluded.

## Build, Test, and Development Commands

There is no compilation step or centralized test suite. Validate the part you change:

- `./install.sh --dry-run` previews symlink and loader changes without modifying home-directory files.
- `bash -n install.sh bin/* claude/statusline-command.sh` checks Bash syntax.
- `zsh -n zshrc` checks the sourced Zsh configuration.
- `git diff --check` catches whitespace errors before committing.

Run `./install.sh` only from the primary checkout, because links created from a disposable worktree will break when that worktree is removed.

## Coding Style & Naming Conventions

Shell scripts use `#!/usr/bin/env bash`, two-space indentation, quoted variable expansions, and defensive settings such as `set -euo pipefail` where appropriate. Prefer small functions with clear lowercase names and local variables. Name command-line tools with lowercase kebab-case (`workflow-update`) and skill directories after the capability they provide. Keep JSON/JSONC formatting consistent with neighboring files.

## Testing Guidelines

For installer changes, exercise both dry-run behavior and idempotency; a second run should report existing links without replacing them. For CLI helpers, test argument validation and the safest non-mutating path available. Document any manual verification in the pull request.

## Commit & Pull Request Guidelines

Recent history favors short, scoped, imperative subjects such as `bin: add deepcode wrapper` and `readme: document the deepcode tool`. Start feature work with `worktree <slug>` and use the reported `worktree/<slug>` checkout. Commit with `atomic-commit "<scoped message>" -- <explicit files...>` so unrelated changes remain uncommitted. Describe behavior and validation in the PR, and link relevant issues. Screenshots are only needed for user-visible terminal or status-line changes. Open PRs against the canonical upstream repository, not a personal fork.
