---
name: using-superpowers
description: Use when starting a development task to orient on the available workflow agents and skills - establishes the plan-driven, TDD, review-gated workflow and which agent or skill to reach for
---

# Using the Workflow

This repo ships a coherent, plan-driven development workflow made of **skills**
(guidance you follow in the main loop) and **agents** (isolated-context
subagents you dispatch to do a scoped job and return a result). This skill is the
map.

## The Rule

**Before acting on a development task, check whether a skill or agent covers
it — and use it.** That includes before clarifying questions and before
exploring the codebase: the skills tell you *how* to explore, plan, and verify.
If a skill turns out wrong for the situation, you don't have to use it — but
check first.

Then announce "Using [skill] to [purpose]" (or "Dispatching [agent] to
[purpose]") and follow it. If it has a checklist, create a todo per item.

User instructions (CLAUDE.md / RULES.md / direct requests) override skills, which
override default behavior. Only skip a skill's workflow when the user has
explicitly said to.

## The Workflow Arc

```
idea
 └─ brainstorming (skill) ............ dialogue → approved spec in docs/specs/
     └─ plan-writer (agent) .......... spec → bite-sized TDD plan in docs/plans/
         └─ execute the plan:
             ├─ subagent-driven-development (skill) — dispatch a fresh
             │    tdd-implementer per task + code-reviewer gate (same session)
             └─ plan-executor (agent) — carry out the whole plan in one
                  isolated session
         └─ finishing-a-development-branch (skill) .. verify → PR against upstream
```

Cross-cutting throughout: `using-git-worktrees` (isolate first),
`systematic-debugger` (any bug), `completion-verifier` (before any "done"
claim), `dispatching-parallel-agents` (independent problems in parallel).

## Agents (dispatch these)

| Agent | Dispatch when |
|-------|---------------|
| `plan-writer` | An approved spec needs a bite-sized TDD implementation plan |
| `plan-executor` | A written plan should be executed end-to-end in one isolated session |
| `tdd-implementer` | One well-specified task/feature/bugfix needs implementing (strict red-green-refactor) |
| `code-reviewer` | A completed diff or branch needs review before it cascades |
| `systematic-debugger` | Any bug, test failure, or unexpected behavior — find root cause before fixing |
| `completion-verifier` | You're about to claim something passes/works/is done — verify it first |

## Skills (follow these in the main loop)

| Skill | Use when |
|-------|----------|
| `brainstorming` | Before ANY creative/feature work — turn an idea into an approved design |
| `subagent-driven-development` | Executing a plan by dispatching a fresh subagent per task |
| `dispatching-parallel-agents` | 2+ independent problems that can be worked concurrently |
| `finishing-a-development-branch` | Implementation done — decide how to integrate (PR/keep/discard) |
| `receiving-code-review` | Feedback arrives — evaluate it technically, don't perform agreement |
| `using-git-worktrees` | Starting work that needs isolation — set up a `worktree` |
| `writing-skills` | Creating or editing a skill (TDD for documentation) |
| `using-superpowers` | This map — orient at the start of a task |

## Skill Priority

Process skills come first — they set the approach — then implementation carries
it out. "Let's build X" → `brainstorming` first. "Fix this bug" →
`systematic-debugger` first.

## Red Flags (you're rationalizing — STOP and check)

"This is just a simple question" (questions are tasks) · "I need more context
first" (the skill check comes before clarifying) · "Let me explore the codebase
first" (skills tell you how) · "This doesn't need a formal skill" (if one exists,
use it) · "I remember this skill" (skills evolve — read the current version).

## Platform Note

These skills are linked into both Claude and Codex. Agents render into each
harness's native subagent format via `bin/build-agents`. When a harness provides
a native worktree tool, `using-git-worktrees` prefers this repo's `worktree`
command; adapt to whatever isolation your harness offers rather than fighting it.
