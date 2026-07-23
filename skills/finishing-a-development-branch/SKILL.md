---
name: finishing-a-development-branch
description: Use when implementation is complete and all tests pass and you need to decide how to integrate the work - presents structured options for opening a PR, keeping, or discarding the branch, following this repo's upstream-PR conventions
---

# Finishing a Development Branch

## Overview

Guide the completion of development work by verifying tests, presenting clear
options, and executing the chosen workflow. This repo's rules shape the menu:
**new work is never merged straight to `main` locally, and PRs always target the
upstream canonical repo, never a fork.**

**Core principle:** Verify tests → detect environment → present options →
execute choice → clean up.

**Announce at start:** "I'm using the finishing-a-development-branch skill to
complete this work."

## Step 1: Verify Tests

Run the project's checks before offering anything. For this dotfiles repo that
means the relevant subset of: `./install.sh --dry-run`, `bin/check-skills`,
`bin/build-agents --check`, `bash -n` on changed scripts, `zsh -n zshrc`,
`git diff --check`. For other projects, the test suite.

**If they fail:** show the failures and stop. Cannot proceed to integration until
they pass.

**If they pass:** continue.

## Step 2: Detect Environment

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
WORKTREE_PATH=$(git rev-parse --show-toplevel)
BRANCH=$(git branch --show-current)
```

`GIT_DIR != GIT_COMMON` and a path under `worktrees/` means you're in a
worktree this repo's tooling created — you own its cleanup. A detached HEAD is
externally managed — no local branch to push until you create one.

## Step 3: Confirm the Base and Remotes

```bash
git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null
git remote -v   # note whether `upstream` exists and where `origin` points
```

PRs target **`upstream`** (the canonical repo). If `origin` is a fork, you'll
push the branch there but open the PR against `upstream`. If the PR's base
branch only exists on the fork/local, push it to `upstream` first so the PR can
target it there.

## Step 4: Present Options

Present exactly these — concise, no extra explanation:

```
Implementation complete. What would you like to do?

1. Push and open a Pull Request (against upstream)
2. Keep the branch as-is (I'll handle it later)
3. Discard this work

Which option?
```

(There is deliberately no "merge to main locally" option — this repo integrates
through upstream PRs.)

## Step 5: Execute the Choice

### Option 1: Push and open a PR

```bash
# Push the branch to the fork remote if origin is a fork, else to origin.
git push -u origin "$BRANCH"
```

Then open the PR against the **upstream** repo's base branch (via `gh pr create
-R <upstream owner/name> --base <base> --head <fork-owner>:<branch>`), describing
the behavior and how it was validated, and linking any relevant issues.

**Do NOT clean up the worktree** — it stays alive so you can address PR feedback.
This repo's `pr-*` tools (`pr-list`, `pr-fix`, `pr-merge`) and the `pr-babysitter`
agent take over from here.

### Option 2: Keep as-is

Report: "Keeping branch `<name>`. Worktree preserved at `<path>`." Don't clean up.

### Option 3: Discard

**Confirm first** — require the user to type `discard`:

```
This will permanently delete:
- Branch <name>
- Commits: <commit-list>
- Worktree at <path>

Type 'discard' to confirm.
```

On exact confirmation, `cd` to the main checkout root, remove the worktree, then
force-delete the branch:

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
git worktree remove "$WORKTREE_PATH"
git worktree prune
git branch -D "$BRANCH"
```

## Step 6: Worktree Cleanup Rules

Only Option 3 removes a worktree. Options 1 and 2 always preserve it.

- Only clean up worktrees under `worktrees/` (this repo's convention) — those are
  ours. Leave harness-owned or externally-created workspaces in place.
- Always `cd` to the main checkout root before `git worktree remove` (removing a
  worktree from inside it fails silently).
- Run `git worktree prune` after removal to clear stale registrations.

## Quick Reference

| Option | Push | Keep worktree | Cleanup branch |
|--------|------|---------------|----------------|
| 1. Open PR (upstream) | yes | yes | — |
| 2. Keep as-is | — | yes | — |
| 3. Discard | — | — | yes (force, after typed confirm) |

## Red Flags

**Never:** proceed with failing tests · merge new work directly to `main` · open
a PR against a fork instead of upstream · force-push without an explicit request ·
remove a worktree you didn't create · run `git worktree remove` from inside the
worktree · discard without a typed `discard` confirmation.

**Always:** verify tests first · target upstream for PRs · keep the worktree
alive for Options 1 and 2 · get typed confirmation before discarding.
