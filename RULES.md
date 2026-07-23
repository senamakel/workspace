# Local Workflow Preferences

- For any new implementation or audit work, run `worktree <slug>` before editing and work inside the reported `./worktree/<slug>` path. The command creates or reuses the matching feature branch and initializes recursive submodules. Do not do new work directly on `main`.

- Make a lot of small, focused commits along the way. Prefer committing coherent checkpoints after each meaningful slice is implemented and validated instead of saving everything for one large final commit.

- Always raise PRs against the **upstream** canonical repo (e.g. `tinyhumansai/*`), never a personal fork. `origin` may point at a fork (e.g. `senamakel/*`); when it does, push the branch and open the PR against the `upstream` remote. If the PR's base branch only exists locally/on the fork, push it to upstream first so the PR can target it there.

- Keep commits atomic with `atomic-commit "<scoped message>" -- path/to/file1 path/to/file2`. List every touched file explicitly; the command unstages unrelated changes, stages only the named paths, and commits only that scope.
