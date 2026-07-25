# Workflow Remote Configuration

## Goal

Configure the five local TinyHumans workflow checkouts and every initialized
repository nested beneath them so pulls come from the canonical TinyHumans
repositories and pushes go to the matching personal forks. Apply the
configuration to the current workspace once and make `workspace-init` establish
the same configuration for future or existing workspaces.

## Remote layout

Each top-level `workflow-*` checkout is an exception to the fork-origin rule.
Its `origin` and `upstream` remotes both point to
`git@github.com:tinyhumansai/<workflow-repository>.git`.

For every initialized submodule recursively:

- `origin` points to `git@github.com:senamakel/<repository>.git`.
- `upstream` points to `git@github.com:tinyhumansai/<repository>.git`.
- `remote.pushDefault` is `origin`.
- Local `main`, when present, tracks `upstream/main`.

Repository names come from each repository's existing GitHub remote URL rather
than its checkout directory. This supports repeated repository names at
different nested paths and avoids deriving identity from submodule aliases.

## Workspace initialization

`workspace-init` continues cloning workflow roots from TinyHumans. After all
missing clones are created, it visits every existing workflow checkout. It
initializes submodules recursively and applies the remote layout to the root and
all initialized descendants. Existing destinations are no longer entirely
opaque: their worktrees and branches remain untouched, but their remotes and
pull/push defaults are repaired idempotently.

Dry-run reports the clone, submodule initialization, and configuration actions
without changing files, Git configuration, or contacting GitHub.

## Failure handling

The command fails if a repository has no recognizable GitHub remote from which
to determine its repository name. It also fails if recursive submodule
initialization or remote configuration fails. It never rewrites `.gitmodules`,
commits, checks out branches, resets worktrees, or fetches branch content beyond
what recursive submodule initialization requires.

## Verification

Automated tests use local repositories and fake GitHub-style remote URLs to
cover:

- the workflow-root `origin` exception;
- fork and canonical remotes for direct and nested submodules;
- `main` pull tracking and default push selection;
- repair of existing workflow checkouts;
- idempotent reruns; and
- inert dry-run behavior.

After the implementation passes tests, run `workspace-init` against
`/home/enamakel/work` and audit every initialized repository recursively.
