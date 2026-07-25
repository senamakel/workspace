# Workflow Remote Configuration Implementation Plan

## Task 1: Add the recursive configurator

**Files:** `bin/workflow-remotes`, `tests/workflow-remotes.sh`

1. Add tests that construct a workflow root with a direct and nested submodule.
2. Assert root remotes remain canonical while descendant origins use the fork.
3. Assert `main` pulls from `upstream`, pushes default to `origin`, and reruns
   are idempotent.
4. Assert dry-run makes no configuration changes.
5. Implement the smallest standalone command that satisfies those tests.
6. Run the focused test, Bash syntax check, and `git diff --check`.
7. Commit the two files atomically.

## Task 2: Integrate workspace initialization

**Files:** `bin/workspace-init`, `tests/workspace-bootstrap.sh`

1. Extend the bootstrap tests to provide the configurator to the isolated test
   environment.
2. Assert new and existing workflow checkouts are recursively initialized and
   configured.
3. Assert dry-run remains inert.
4. Invoke `workflow-remotes` for every workflow destination after clone
   handling, forwarding dry-run.
5. Run bootstrap, configurator, and existing workflow-update tests plus Bash
   syntax and whitespace checks.
6. Commit the integration atomically.

## Task 3: Apply and audit

1. Run the installed worktree command against `/home/enamakel/work`.
2. Enumerate each workflow root and all initialized recursive submodules.
3. Verify exact `origin`, `upstream`, `remote.pushDefault`, and `main` tracking
   values.
4. Report repositories that lack a local `main` separately; do not create or
   check out branches during configuration.
