# Open-source contribution state

This directory is the shared, Git-backed handoff between the open-source
researcher, issue triager, and contributor agents.

- `repositories.json` is the researcher-owned catalog. The researcher may add,
  refresh, pause, or retire repositories, but never selects or works issues.
- `issues/<owner>--<repo>--<number>.json` is one issue-sized queue and lifecycle
  record. One file per issue keeps independent workers from conflicting.

Run `bin/check-open-source-state` before committing any state change.

`open-source-work` is the agent-facing boundary between this control-plane
checkout and external repositories:

```sh
open-source-work repos
open-source-work queue
open-source-work show 'owner/repo#123'
open-source-work prepare 'owner/repo#123'
open-source-work run 'owner/repo#123' -- git status --short
```

The first three commands only read shared state. `prepare` requires a durable
claim, verifies the fork/canonical remotes, and creates the exact worktree
recorded by the claim. `run` executes a command from that target worktree, so
agents do not accidentally explore or modify this repository.

Contributor launches cap new upstream pull requests at five per UTC day across
the shared state. Before target work begins, a contributor atomically reserves
a slot with `claim.pr_slot_date`; records already opened that day also count.
The launcher reduces its effective batch allowance by those durable slots.
Agents recheck the count immediately before opening each PR; existing PR
babysitting does not consume a new slot.

## State synchronization

Operational state changes are the narrow exception to the normal pull-request
rule for this repository. From the primary `workspace` checkout on `main`, an
agent must:

1. Require a clean state path and run `git pull --rebase`.
2. Change only `open-source/repositories.json` or one issue record.
3. Validate with `bin/check-open-source-state`.
4. Commit only the changed state file with `atomic-commit`.
5. Run `git pull --rebase` again and push immediately.

If a rebase conflicts on the same issue record, another worker won the claim.
Abort that claim, preserve the winning record, and select another queued issue.
Never force-push state.

## Lifecycle

Issue states are:

`queued → claimed → in_progress → pr_open → waiting → green → merged`

An item may instead become `blocked`, `rejected`, `stale`, or `closed`. Every
transition appends a timestamped history entry. `claimed` is valid only after
the claim commit has reached `origin/main`; target-repository work must not
start before then.
