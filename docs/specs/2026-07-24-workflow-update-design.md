# Workflow Update Design

## Purpose

`workflow-update` updates the direct submodules of a workflow superproject and
records their new commits in the superproject. It does not update, merge, or
switch the superproject itself.

## Required behavior

The command:

1. Finds the superproject root from any directory inside it and requires a
   `.gitmodules` file.
2. Initializes the submodules declared directly in that file without recursing
   into nested submodules.
3. Processes each declared submodule independently:
   - Try to fetch and resolve `upstream/main`.
   - If `upstream` is absent, its fetch fails, or `upstream/main` does not
     resolve, warn and try `origin/main`.
   - Fail when neither remote provides a resolvable `main`.
   - Force the submodule's local `main` branch to the selected remote commit.
   - Check out local `main` and hard-reset it to that commit.
4. Stages only submodule gitlinks whose recorded commits changed.
5. Commits staged pointer changes as `Update submodule pointers`, unless
   `--no-commit` was supplied.
6. Exits successfully without a commit when no submodule pointer changed.

## Destructive semantics

The forced branch update intentionally discards divergent local `main` commits
and tracked uncommitted changes inside each submodule. Untracked files are not
cleaned. If an untracked file prevents Git from switching or resetting the
branch, the command fails with Git's error rather than deleting that file.

The command does not protect against a partially updated run: if a later
submodule fails, earlier submodules may already have been reset. No pointer
commit is created after a failure.

## Remote selection

Remote preference is evaluated per submodule. A usable candidate must both
fetch successfully and expose `refs/remotes/<remote>/main` after the fetch.
`upstream` is always attempted first when configured. `origin` is the only
fallback. Remote default-branch metadata and `master` are ignored.

## Interface

The existing interface remains:

```text
workflow-update [--no-commit]
```

Unknown arguments fail. `--help` describes the first-level, destructive
local-`main` behavior. Status output identifies the selected remote and commit
for each submodule and reports whether a superproject pointer changed.

## Verification

Shell integration tests will create temporary bare remotes, submodule
repositories, and a superproject to verify:

- `upstream/main` is preferred over a different `origin/main`;
- `origin/main` is used when `upstream/main` cannot be resolved;
- each submodule ends on local `main` at the selected remote commit;
- divergent local commits and tracked changes are discarded;
- nested submodules are not initialized or updated;
- the superproject branch is not fetched, merged, or switched;
- changed gitlinks are staged and committed;
- `--no-commit` stages without committing;
- an already-current run creates no commit; and
- failure occurs when neither remote provides `main`.

The repository's shell syntax, skill validation, and whitespace checks remain
part of final validation.
