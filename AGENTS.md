# Repository Guidelines

## Project Structure & Module Organization

This repository is the source of truth for personal shell and coding-agent configuration. `install.sh` links managed files into the user’s home directory. Shared workflow rules live in `RULES.md`; shared agent sources live in `agents/<name>/` and are rendered into harness-native files. Shared skills live in `skills/<name>/` and are linked into both Claude and Codex. Shared Medulla workflow definitions live in `workflows/<name>.json`, and the whole directory is symlinked over `~/.medulla/<account id>/workflows/` — for the active account named by `~/.medulla/active_user.toml` and any other account already on the machine. It is the directory, not each file: Medulla saves a flow by renaming a temporary file over the target, which replaces a per-file symlink with a regular file, so flows edited or created in Medulla never reached this repository. With the directory linked, the rename lands inside `workflows/` and every flow Medulla writes is a change in this checkout. Medulla scopes its workflow store per account, so the flat `~/.medulla/workflows/` is *not* read; `install.sh` removes the links it used to leave there. The portable half of Medulla's own settings lives in `medulla/config.toml` and is merged into each account's live `config.toml` by `bin/medulla-config-merge` — whole sections at a time, leaving `[fleet]`, `[harness]` and `[backend]` as that machine wrote them. It is merged rather than linked for the same rename reason. Hooks shared across harnesses belong in that file's `[[hooks]]` array rather than in `claude/settings.json`, so one declaration reaches every harness Medulla launches. Shared git settings live in `gitconfig` and are pulled into `~/.gitconfig` with `include.path` rather than replacing it, so machine-local values (signing key, GPG path, credential helpers) stay put. Other harness-specific configuration is under `claude/`, `codex/`, and `opencode/`. Executable helpers belong in `bin/`, while custom shell aliases and functions live in `zshrc`. Keep every skill self-contained, with `SKILL.md` as its entry point and optional resources inside the same directory.

Do not commit machine-local credentials or generated state. In particular, `~/.codex/config.toml` and the local OpenCode package/config files are intentionally excluded, as are the credential maps the `bin/` helpers read (`~/.config/langfuse/envs.tsv`, `~/.config/langfuse/projects.tsv`, `~/.config/sentry/repos.tsv`). Tools may point at existing secret files by path, but must never copy a key into this repository.

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
- `tests/auto-commit.sh` exercises the auto-commit hook's offline logic — the
  tool-call counter, the repository allowlist, the detached-HEAD and
  in-progress-operation guards, credential filtering, and the subject fallback —
  with a stubbed model and no credentials.
- `tests/langfuse-lib.sh` exercises the Langfuse helpers' offline logic —
  environment resolution, project presets, time windows, and paging — with a
  stubbed API and no credentials.
- `bash -n install.sh bin/* claude/statusline-command.sh` checks Bash syntax.
- `zsh -n zshrc` checks the sourced Zsh configuration.
- `git diff --check` catches whitespace errors before committing.

Run `./install.sh` only from the primary checkout, because links created from a disposable worktree will break when that worktree is removed.

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
