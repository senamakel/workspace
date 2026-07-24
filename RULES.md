# Local Workflow Preferences

- Default to executing, not planning. When a task is clear and well-scoped, make the change directly — do not open a separate plan or design phase, and do not stop to ask for approval before starting. Reserve an explicit plan or design doc for work that is genuinely large, ambiguous, risky, or when the user explicitly asks for one.

- Don't stop to ask when the next step is obvious and the request already authorizes it. Pick the sensible default, proceed through the whole task, and report what you did at the end. Ask only when you are truly blocked on a decision that is the user's to make — an irreversible or destructive action, or a real fork with no clear default.

- For any new implementation or audit work, run `worktree <slug>` before editing and work inside the reported `./worktrees/<slug>` path. The command creates or reuses the matching feature branch and initializes recursive submodules. Do not do new work directly on `main`.

- Commit after every step. As soon as a step is implemented and validated, commit it before starting the next one — do not batch multiple steps into one commit or defer commits to the end. Small, frequent commits are the default, not the exception; when in doubt, commit.

- Always raise PRs against the **upstream** canonical repo (e.g. `tinyhumansai/*`), never a personal fork. `origin` may point at a fork (e.g. `senamakel/*`); when it does, push the branch and open the PR against the `upstream` remote. If the PR's base branch only exists locally/on the fork, push it to upstream first so the PR can target it there.

- Keep commits atomic with `atomic-commit "<scoped message>" -- path/to/file1 path/to/file2`. List every touched file explicitly; the command unstages unrelated changes, stages only the named paths, and commits only that scope.
