---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from the current workspace or before executing an implementation plan - ensures an isolated worktree exists, preferring this repo's worktree command
---

# Using Git Worktrees

## Overview

Ensure work happens in an isolated workspace before you touch code. This repo
ships a `worktree` command that is the preferred mechanism — it creates or
reuses a branch, places the checkout under `worktrees/<slug>`, and initializes
submodules recursively.

**Core principle:** Detect existing isolation first. Then use the `worktree`
command. Fall back to raw `git worktree` only if the command is unavailable.

**Announce at start:** "I'm using the using-git-worktrees skill to set up an
isolated workspace."

## Step 0: Detect Existing Isolation

Before creating anything, check whether you're already isolated.

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

**Submodule guard:** `GIT_DIR != GIT_COMMON` is also true inside a submodule.
Before concluding "already in a worktree," confirm you're not in one:

```bash
git rev-parse --show-superproject-working-tree 2>/dev/null  # prints a path → submodule
```

**If `GIT_DIR != GIT_COMMON` (and not a submodule):** you're already in a linked
worktree. Skip to Step 2. Do NOT nest another worktree. Report the path and
branch.

**If `GIT_DIR == GIT_COMMON` (or in a submodule):** you're in a normal checkout.
Per this repo's rules, new implementation or audit work does not happen on
`main` — proceed to Step 1.

## Step 1: Create the Worktree

### 1a. The `worktree` command (preferred)

```bash
worktree <slug>            # or: worktree <slug> --json
```

It creates or safely reuses branch `<slug>` from the current `HEAD`, checks it
out at `<repo>/worktrees/<slug>`, initializes submodules recursively, and prints
a `WORKTREE_READY` report ending in the `cd` command to run. `cd` into the
reported path and continue.

The command is idempotent: if the branch and registered worktree already exist
and match, it reuses them rather than failing.

### 1b. Raw git fallback (only if `worktree` is unavailable)

Only if the `worktree` command is not on PATH:

```bash
# worktrees/ is already gitignored in this repo
git worktree add worktrees/<slug> -b <slug>
cd worktrees/<slug>
git submodule update --init --recursive
```

If `git worktree add` fails with a sandbox/permission error, tell the user the
sandbox blocked worktree creation and you're working in place instead; then run
setup and baseline tests where you are.

## Step 2: Project Setup

Auto-detect and run the appropriate setup for the project:

```bash
[ -f package.json ] && npm install
[ -f Cargo.toml ] && cargo build
[ -f requirements.txt ] && pip install -r requirements.txt
[ -f pyproject.toml ] && poetry install
[ -f go.mod ] && go mod download
```

(For this dotfiles repo specifically there is no build step — see AGENTS.md for
the per-change validation commands.)

## Step 3: Verify a Clean Baseline

Run the project's tests so you start from green:

```bash
# project-appropriate: npm test / cargo test / pytest / go test ./...
```

**Tests fail:** report the failures and ask whether to proceed or investigate —
so you can later tell new breakage from pre-existing.
**Tests pass:** report ready.

### Report

```
Worktree ready at <full-path> on branch <slug>
Baseline: <N tests, 0 failures | no test suite>
Ready to implement <feature-name>
```

## Quick Reference

| Situation | Action |
|-----------|--------|
| Already in a linked worktree | Skip creation (Step 0) |
| In a submodule | Treat as a normal repo (Step 0 guard) |
| `worktree` command available | Use it (Step 1a) |
| `worktree` command missing | Raw `git worktree` under `worktrees/` (Step 1b) |
| Sandbox blocks creation | Work in place, tell the user |
| Baseline tests fail | Report + ask before proceeding |

## Red Flags

**Never:** create a worktree when Step 0 already detects isolation · nest a
worktree inside a worktree · start new work on `main` · skip baseline
verification · proceed past failing baseline tests without asking.

**Always:** run Step 0 first · prefer the `worktree` command · verify a clean
baseline before implementing.
