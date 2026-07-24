# Workflow Update Implementation Plan

> **For agentic workers:** execute this plan task-by-task using the
> subagent-driven-development skill (dispatch a fresh tdd-implementer agent per
> task, then a code-reviewer agent) or the plan-executor agent. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `workflow-update` update only direct submodules to a resolvable remote `main`, force each local `main` to that commit, and record only changed superproject gitlinks.
**Architecture:** Keep the feature as one defensive Bash command and add a self-contained shell integration suite that builds disposable Git repositories and bare remotes. The command discovers the superproject once, selects `upstream/main` or `origin/main` independently for each direct submodule, then stages and optionally commits changed gitlinks without fetching, merging, or switching the superproject.
**Tech Stack:** Bash, Git CLI, temporary local bare repositories, repository-native syntax and whitespace validation.

## Global Constraints

- Preserve the existing interface exactly: `workflow-update [--no-commit]`; `-h` and `--help` remain supported, and every unknown or extra argument fails.
- Require a `.gitmodules` file at the superproject root discovered from any directory inside the superproject.
- Initialize only submodules declared directly in `.gitmodules`; never recurse into nested submodules.
- Attempt only `upstream/main`, then `origin/main`, independently for every direct submodule; ignore remote HEAD metadata and `master`.
- A remote is usable only when it is configured, fetch succeeds, and `refs/remotes/<remote>/main` resolves to a commit after that fetch.
- Force the submodule's local `main` and tracked working tree to the selected commit; preserve untracked files and let Git fail if an untracked obstruction prevents checkout.
- Do not make the run transactional: an earlier submodule may remain reset when a later one fails, but no pointer commit may be created after failure.
- Stage only direct-submodule gitlinks whose recorded commits changed.
- Commit changed gitlinks with subject `Update submodule pointers` unless `--no-commit` was supplied.
- Exit successfully without a commit when all recorded gitlinks are current.
- Use Bash syntax compatible with the repository's existing scripts; add no test framework dependency.
- Commit each completed task with `atomic-commit` and the exact paths listed in that task.

## File Structure

- **Create:** `tests/workflow-update.sh` — executable, dependency-free integration suite with repository factories, assertions, and isolated behavior tests.
- **Modify:** `bin/workflow-update` — argument handling, help text, direct-submodule initialization, per-submodule remote selection and forced local-`main` synchronization, gitlink staging, and optional commit.
- **Reference only:** `docs/specs/2026-07-24-workflow-update-design.md` — approved behavioral contract; do not alter during implementation.

---

## Task 1: Lock the command boundary and stop mutating the superproject

**Files**

- Create: `tests/workflow-update.sh`
- Modify: `bin/workflow-update:1-70`

**Interfaces**

- Consumes: `workflow-update [--no-commit]`, Git's `rev-parse --show-toplevel`, and a root `.gitmodules` file.
- Produces: `usage()` with no parameters; successful `-h`/`--help`; failure for unknown or extra arguments; a main path that never fetches, merges, checks out, or resets the superproject.

- [ ] Create `tests/workflow-update.sh` with the following harness and first two regression tests:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND="$ROOT/bin/workflow-update"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/workflow-update-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

PASS_COUNT=0

fail_test() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [ "$actual" = "$expected" ] || fail_test "$message: expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail_test "$message: missing '$needle'" ;;
  esac
}

assert_file_missing() {
  local path="$1" message="$2"
  [ ! -e "$path" ] || fail_test "$message: found $path"
}

run_test() {
  local name="$1"
  shift
  "$@"
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s - %s\n' "$PASS_COUNT" "$name"
}

configure_identity() {
  git -C "$1" config user.name "Workflow Update Test"
  git -C "$1" config user.email "workflow-update@example.invalid"
}

make_repo_with_empty_gitmodules() {
  local repo="$1"
  git init -q "$repo"
  configure_identity "$repo"
  : > "$repo/.gitmodules"
  git -C "$repo" add .gitmodules
  git -C "$repo" commit -qm "Initialize superproject"
}

test_interface_validation() {
  local output status

  output="$("$COMMAND" --help)"
  assert_contains "$output" "workflow-update [--no-commit]" "help shows the interface"
  assert_contains "$output" "local main" "help describes the forced local branch"
  assert_contains "$output" "first-level" "help describes direct submodules"
  assert_contains "$output" "discard" "help warns about destructive behavior"

  set +e
  output="$("$COMMAND" --unknown 2>&1)"
  status=$?
  set -e
  assert_eq "1" "$status" "unknown argument fails"
  assert_contains "$output" "unknown argument: --unknown" "unknown argument is identified"

  set +e
  output="$("$COMMAND" --no-commit extra 2>&1)"
  status=$?
  set -e
  assert_eq "1" "$status" "extra argument fails"
  assert_contains "$output" "unknown argument: extra" "extra argument is identified"
}

test_superproject_is_not_synchronized() {
  local bare seed super before_head before_branch before_remote output
  bare="$TEST_ROOT/super-remote.git"
  seed="$TEST_ROOT/super-seed"
  super="$TEST_ROOT/super"

  git init -q --bare "$bare"
  make_repo_with_empty_gitmodules "$seed"
  git -C "$seed" branch -M main
  git -C "$seed" remote add origin "$bare"
  git -C "$seed" push -q -u origin main
  git --git-dir="$bare" symbolic-ref HEAD refs/heads/main
  git clone -q "$bare" "$super"
  configure_identity "$super"

  git -C "$seed" checkout -qb remote-only
  printf 'remote-only\n' > "$seed/remote-only.txt"
  git -C "$seed" add remote-only.txt
  git -C "$seed" commit -qm "Add remote-only change"
  git -C "$seed" push -q origin HEAD:main

  git -C "$super" checkout -qb local-work
  before_head="$(git -C "$super" rev-parse HEAD)"
  before_branch="$(git -C "$super" branch --show-current)"
  before_remote="$(git -C "$super" rev-parse refs/remotes/origin/main)"
  mkdir -p "$super/nested/directory"

  output="$(cd "$super/nested/directory" && "$COMMAND" --no-commit)"

  assert_eq "$before_head" "$(git -C "$super" rev-parse HEAD)" "superproject HEAD is unchanged"
  assert_eq "$before_branch" "$(git -C "$super" branch --show-current)" "superproject branch is unchanged"
  assert_eq "$before_remote" "$(git -C "$super" rev-parse refs/remotes/origin/main)" "superproject remote ref is not fetched"
  assert_file_missing "$super/remote-only.txt" "superproject remote commit was not merged"
  assert_contains "$output" "all submodule pointers already up to date" "empty direct-submodule set succeeds"
}

run_test "validates the command interface" test_interface_validation
run_test "does not synchronize the superproject" test_superproject_is_not_synchronized
printf '1..%s\n' "$PASS_COUNT"
```

- [ ] Mark the test executable with `chmod +x tests/workflow-update.sh`.

- [ ] Run `tests/workflow-update.sh` and verify it fails because the current help still describes merging the superproject or because the current command fetches and merges the remote-only commit:

```text
not ok - help describes the forced local branch: missing 'local main'
```

- [ ] Replace the header, argument parser, and superproject synchronization block in `bin/workflow-update` with this minimal boundary implementation, retaining the existing color/log helpers and the existing submodule loop temporarily:

```bash
#!/usr/bin/env bash
# workflow-update — update direct submodules and record their gitlinks.
set -euo pipefail

usage() {
  cat <<'EOF'
workflow-update [--no-commit]

Update each first-level submodule to upstream/main, falling back to origin/main.
Each submodule is forced onto local main at the selected remote commit, discarding
divergent local main commits and tracked changes. Nested submodules are untouched.
The superproject is not fetched, merged, switched, or reset.

Options:
  --no-commit  stage changed submodule pointers without committing
  -h, --help   show this help
EOF
}
```

Use this parser after the log helpers:

```bash
COMMIT=1
if [ "$#" -gt 1 ]; then
  fail "unknown argument: $2"
  exit 1
fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-commit)
      [ "$COMMIT" = "1" ] || { fail "unknown argument: $1"; exit 1; }
      COMMIT=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      exit 1
      ;;
  esac
  shift
done
```

Use this root discovery and initialization in place of the current superproject fetch/merge section:

```bash
TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { fail "not inside a git repository"; exit 1; }
cd "$TOPLEVEL"
[ -f .gitmodules ] || { fail "no .gitmodules here — not a workflow superproject"; exit 1; }

git submodule sync
git submodule update --init
```

Delete the superproject `git fetch` and `git merge`. Leave `canonical_remote()`,
`default_branch()`, and the existing submodule loop in place for this commit so
the command remains functional; Task 2 replaces that complete submodule path
and then removes both obsolete helpers.

- [ ] Run `tests/workflow-update.sh`, `bash -n bin/workflow-update tests/workflow-update.sh`, and `git diff --check`; expect both integration tests to print `ok`, Bash syntax to exit zero, and no whitespace errors.

- [ ] Commit only this slice:

```bash
atomic-commit "bin: stop synchronizing workflow superprojects" -- bin/workflow-update tests/workflow-update.sh
```

---

## Task 2: Select a usable `main` per submodule and force local `main`

**Files**

- Modify: `tests/workflow-update.sh`
- Modify: `bin/workflow-update:45-115`

**Interfaces**

- Consumes: direct submodule path, configured Git remotes, and `refs/remotes/<remote>/main`.
- Produces: `select_main <submodule-path>`, setting global `SELECTED_REMOTE` and `SELECTED_COMMIT`; `force_local_main <submodule-path> <commit>`; warning output for each unusable candidate; failure when neither candidate resolves.

- [ ] Add these repository factories after `make_repo_with_empty_gitmodules()` in `tests/workflow-update.sh`:

```bash
make_remote() {
  local name="$1"
  local bare="$TEST_ROOT/$name.git"
  local seed="$TEST_ROOT/$name-seed"

  git init -q --bare "$bare"
  git init -q "$seed"
  configure_identity "$seed"
  printf '%s base\n' "$name" > "$seed/state.txt"
  git -C "$seed" add state.txt
  git -C "$seed" commit -qm "$name base"
  git -C "$seed" branch -M main
  git -C "$seed" remote add origin "$bare"
  git -C "$seed" push -q -u origin main
  git --git-dir="$bare" symbolic-ref HEAD refs/heads/main
  printf '%s\n' "$bare"
}

advance_remote() {
  local name="$1" text="$2"
  local seed="$TEST_ROOT/$name-seed"
  printf '%s\n' "$text" > "$seed/state.txt"
  git -C "$seed" add state.txt
  git -C "$seed" commit -qm "$text"
  git -C "$seed" push -q origin main
  git -C "$seed" rev-parse HEAD
}

make_superproject_with_submodule() {
  local name="$1" remote="$2"
  local super="$TEST_ROOT/$name"

  git init -q "$super"
  configure_identity "$super"
  git -c protocol.file.allow=always -C "$super" submodule add -q "$remote" modules/alpha
  git -C "$super" commit -qm "Add alpha submodule"
  printf '%s\n' "$super"
}
```

- [ ] Add these three tests above the `run_test` calls:

```bash
test_prefers_upstream_and_forces_local_main() {
  local origin upstream super selected output
  origin="$(make_remote preference-origin)"
  upstream="$(make_remote preference-upstream)"
  super="$(make_superproject_with_submodule preference-super "$origin")"
  git -C "$super/modules/alpha" remote add upstream "$upstream"
  advance_remote preference-origin "origin tip" >/dev/null
  selected="$(advance_remote preference-upstream "upstream tip")"

  git -C "$super/modules/alpha" checkout -qb divergent
  printf 'tracked dirt\n' > "$super/modules/alpha/state.txt"
  printf 'preserve me\n' > "$super/modules/alpha/untracked.txt"

  output="$(cd "$super/modules" && GIT_ALLOW_PROTOCOL=file "$COMMAND" --no-commit 2>&1)"

  assert_eq "main" "$(git -C "$super/modules/alpha" branch --show-current)" "submodule ends on local main"
  assert_eq "$selected" "$(git -C "$super/modules/alpha" rev-parse HEAD)" "upstream main is selected"
  assert_eq "$selected" "$(git -C "$super/modules/alpha" rev-parse refs/heads/main)" "local main is forced"
  assert_eq "upstream tip" "$(cat "$super/modules/alpha/state.txt")" "tracked changes are discarded"
  assert_eq "preserve me" "$(cat "$super/modules/alpha/untracked.txt")" "untracked files are preserved"
  assert_contains "$output" "upstream/$selected" "status identifies selected remote and commit"
}

test_origin_fallback_conditions() {
  local condition origin upstream super selected output
  for condition in absent fetch-failure missing-main; do
    origin="$(make_remote "fallback-$condition-origin")"
    super="$(make_superproject_with_submodule "fallback-$condition-super" "$origin")"
    selected="$(advance_remote "fallback-$condition-origin" "$condition origin tip")"

    case "$condition" in
      absent)
        ;;
      fetch-failure)
        git -C "$super/modules/alpha" remote add upstream "$TEST_ROOT/does-not-exist.git"
        ;;
      missing-main)
        upstream="$(make_remote fallback-missing-main-upstream)"
        git --git-dir="$upstream" branch -m main master
        git -C "$super/modules/alpha" remote add upstream "$upstream"
        ;;
    esac

    output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" --no-commit 2>&1)"

    assert_eq "$selected" "$(git -C "$super/modules/alpha" rev-parse HEAD)" "$condition falls back to origin main"
    assert_contains "$output" "[WARN]" "$condition warns about unusable upstream"
    assert_contains "$output" "origin/$selected" "$condition status identifies fallback remote and commit"
  done
}

test_fails_without_remote_main() {
  local origin super before status output
  origin="$(make_remote missing-main-origin)"
  super="$(make_superproject_with_submodule missing-main-super "$origin")"
  git --git-dir="$origin" branch -m main master
  git -C "$super/modules/alpha" update-ref -d refs/remotes/origin/main
  before="$(git -C "$super" rev-parse HEAD)"

  set +e
  output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" 2>&1)"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail_test "missing remote main must fail"
  assert_contains "$output" "neither upstream/main nor origin/main" "failure identifies required refs"
  assert_eq "$before" "$(git -C "$super" rev-parse HEAD)" "failure creates no pointer commit"
}
```

Add these invocations before the TAP plan line:

```bash
run_test "prefers upstream main and forces local main" test_prefers_upstream_and_forces_local_main
run_test "falls back to origin for every unusable upstream condition" test_origin_fallback_conditions
run_test "fails when neither remote exposes main" test_fails_without_remote_main
```

- [ ] Run `tests/workflow-update.sh` and verify at least the preference test fails because the current implementation chooses remote default metadata and checks out a detached remote-tracking ref:

```text
not ok - submodule ends on local main: expected 'main', got ''
```

- [ ] Add these helpers before the submodule loop in `bin/workflow-update`:

```bash
select_main() {
  local dir="$1" candidate ref commit
  for candidate in upstream origin; do
    if ! git -C "$dir" remote get-url "$candidate" >/dev/null 2>&1; then
      warn "$dir: $candidate is not configured"
      continue
    fi
    if ! git -C "$dir" fetch "$candidate" --prune; then
      warn "$dir: failed to fetch $candidate"
      continue
    fi
    ref="refs/remotes/$candidate/main"
    if ! commit="$(git -C "$dir" rev-parse --verify "$ref^{commit}" 2>/dev/null)"; then
      warn "$dir: $candidate/main does not resolve to a commit"
      continue
    fi
    SELECTED_REMOTE="$candidate"
    SELECTED_COMMIT="$commit"
    return 0
  done
  fail "$dir: neither upstream/main nor origin/main is available"
  return 1
}

force_local_main() {
  local dir="$1" commit="$2" current
  git -C "$dir" reset --hard HEAD
  current="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ "$current" != "main" ]; then
    git -C "$dir" branch -f main "$commit"
    git -C "$dir" checkout --quiet main
  fi
  git -C "$dir" reset --hard "$commit"
}
```

The first reset deliberately discards tracked changes without `checkout -f`; the ordinary checkout therefore preserves untracked files and fails if an untracked path obstructs switching to `main`.

- [ ] Remove the now-unused `canonical_remote()` and `default_branch()` helpers,
then replace the current submodule loop with this direct-path loop:

```bash
CHANGED=0
while IFS= read -r SM_PATH; do
  [ -n "$SM_PATH" ] || continue
  [ -d "$SM_PATH/.git" ] || [ -f "$SM_PATH/.git" ] \
    || { fail "$SM_PATH: submodule was not initialized"; exit 1; }

  select_main "$SM_PATH"
  RECORDED="$(git rev-parse "HEAD:$SM_PATH")"
  force_local_main "$SM_PATH" "$SELECTED_COMMIT"
  info "$SM_PATH: selected $SELECTED_REMOTE/$SELECTED_COMMIT"

  if [ "$RECORDED" = "$SELECTED_COMMIT" ]; then
    info "$SM_PATH: superproject pointer unchanged"
  else
    git add -- "$SM_PATH"
    pass "$SM_PATH: superproject pointer changed ($RECORDED -> $SELECTED_COMMIT)"
    CHANGED=1
  fi
done < <(
  git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null \
    | sed 's/^[^ ]* //'
)
```

- [ ] Run `tests/workflow-update.sh`, `bash -n bin/workflow-update tests/workflow-update.sh`, and `git diff --check`; expect five passing integration tests and zero syntax or whitespace errors.

- [ ] Commit only this slice:

```bash
atomic-commit "bin: force submodules to available remote main" -- bin/workflow-update tests/workflow-update.sh
```

---

## Task 3: Record only changed direct gitlinks and cover commit modes

**Files**

- Modify: `tests/workflow-update.sh`
- Modify: `bin/workflow-update:90-135`

**Interfaces**

- Consumes: `CHANGED_PATHS`, containing only direct submodule paths whose `HEAD:<path>` differs from `SELECTED_COMMIT`, plus the `COMMIT` flag.
- Produces: staged changed gitlinks; an optional path-limited `Update submodule pointers` commit; success with no commit when no gitlink changes; no nested-submodule initialization.

- [ ] Add this nested-repository factory after the other factory functions in `tests/workflow-update.sh`:

```bash
make_remote_with_nested_submodule() {
  local nested parent
  nested="$(make_remote nested-child)"
  parent="$(make_remote nested-parent)"
  git -c protocol.file.allow=always -C "$TEST_ROOT/nested-parent-seed" \
    submodule add -q "$nested" vendor/child
  git -C "$TEST_ROOT/nested-parent-seed" commit -qm "Add nested child"
  git -C "$TEST_ROOT/nested-parent-seed" push -q origin main
  printf '%s\n' "$parent"
}
```

- [ ] Add these three tests above the `run_test` calls:

```bash
test_commits_only_changed_gitlinks() {
  local origin super selected previous_head
  origin="$(make_remote commit-origin)"
  super="$(make_superproject_with_submodule commit-super "$origin")"
  selected="$(advance_remote commit-origin "committed pointer tip")"
  printf 'keep staged\n' > "$super/unrelated.txt"
  git -C "$super" add unrelated.txt
  previous_head="$(git -C "$super" rev-parse HEAD)"

  (cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" >/dev/null)

  assert_eq "Update submodule pointers" "$(git -C "$super" log -1 --format=%s)" "pointer commit subject is exact"
  assert_eq "$previous_head" "$(git -C "$super" rev-parse HEAD^)" "exactly one pointer commit is created"
  assert_eq "$selected" "$(git -C "$super" rev-parse HEAD:modules/alpha)" "commit records selected gitlink"
  assert_eq "A  unrelated.txt" "$(git -C "$super" status --short unrelated.txt)" "unrelated staged file is not committed"
}

test_no_commit_and_already_current_modes() {
  local origin super selected before output
  origin="$(make_remote modes-origin)"
  super="$(make_superproject_with_submodule modes-super "$origin")"
  selected="$(advance_remote modes-origin "staged pointer tip")"
  before="$(git -C "$super" rev-parse HEAD)"

  output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" --no-commit)"
  assert_eq "$before" "$(git -C "$super" rev-parse HEAD)" "--no-commit preserves superproject HEAD"
  assert_eq "$selected" "$(git -C "$super" rev-parse :modules/alpha)" "--no-commit stages selected gitlink"
  assert_contains "$output" "commit skipped (--no-commit)" "--no-commit reports staging"

  git -C "$super" commit -qm "Record staged pointer"
  before="$(git -C "$super" rev-parse HEAD)"
  output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND")"
  assert_eq "$before" "$(git -C "$super" rev-parse HEAD)" "current run creates no commit"
  assert_contains "$output" "all submodule pointers already up to date" "current run reports no changes"
}

test_does_not_initialize_nested_submodules() {
  local parent super
  parent="$(make_remote_with_nested_submodule)"
  super="$(make_superproject_with_submodule nested-super "$parent")"
  git -C "$super/modules/alpha" remote add upstream "$parent"
  git -C "$super/modules/alpha" fetch -q upstream main
  git -C "$super/modules/alpha" checkout -q main
  git -C "$super/modules/alpha" reset -q --hard refs/remotes/upstream/main
  git -C "$super" add modules/alpha
  git -C "$super" commit -qm "Record parent with nested declaration"

  (cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" --no-commit >/dev/null)

  assert_file_missing "$super/modules/alpha/vendor/child/.git" "nested submodule is not initialized"
}
```

Add these invocations before the TAP plan line:

```bash
run_test "commits only changed gitlinks" test_commits_only_changed_gitlinks
run_test "supports no-commit and already-current modes" test_no_commit_and_already_current_modes
run_test "does not initialize nested submodules" test_does_not_initialize_nested_submodules
```

- [ ] Run `tests/workflow-update.sh` and verify the commit-scope test fails if the implementation uses an unrestricted `git commit`, because `unrelated.txt` is included:

```text
not ok - unrelated staged file is not committed: expected 'A  unrelated.txt', got ''
```

- [ ] Replace scalar `CHANGED=0` with a Bash array and append paths only in the changed-gitlink branch:

```bash
CHANGED_PATHS=()
```

```bash
git add -- "$SM_PATH"
CHANGED_PATHS+=("$SM_PATH")
pass "$SM_PATH: superproject pointer changed ($RECORDED -> $SELECTED_COMMIT)"
```

- [ ] Replace the final commit block with this path-limited behavior:

```bash
if [ "${#CHANGED_PATHS[@]}" -eq 0 ]; then
  pass "all submodule pointers already up to date"
elif [ "$COMMIT" = "1" ]; then
  git commit -m "Update submodule pointers" -- "${CHANGED_PATHS[@]}"
  pass "committed submodule pointer update"
else
  info "pointer changes staged; commit skipped (--no-commit)"
fi
```

Using explicit paths keeps unrelated pre-existing index entries staged but out of the generated pointer commit.

- [ ] Run the complete feature suite twice to prove repeatability:

```bash
tests/workflow-update.sh
tests/workflow-update.sh
```

Expect eight `ok` lines and `1..8` on each run.

- [ ] Run all repository validation gates relevant to the changed shell command and new test:

```bash
bash -n install.sh bin/* claude/statusline-command.sh tests/workflow-update.sh
zsh -n zshrc
bin/check-skills
./install.sh --dry-run
git diff --check
```

Expect every command to exit zero. Run only the dry-run installer from this disposable worktree; do not run `./install.sh`, because links created from a disposable worktree would break when it is removed.

- [ ] Review the final diff against every section of `docs/specs/2026-07-24-workflow-update-design.md`, paying particular attention to no superproject Git operations, exact `main` refs, first-level-only initialization, destructive tracked-file semantics, path-limited commits, and failure before any pointer commit.

- [ ] Commit only this slice:

```bash
atomic-commit "test: cover workflow submodule pointer updates" -- bin/workflow-update tests/workflow-update.sh
```

## Plan Coverage Map

- **Purpose and superproject boundary:** Task 1.
- **Root discovery, `.gitmodules`, interface, help, unknown arguments:** Task 1.
- **Per-submodule `upstream/main` preference and `origin/main` fallback:** Task 2.
- **Forced local `main`, divergent commit removal, tracked-change discard, untracked obstruction semantics:** Task 2.
- **Failure when neither candidate provides `main`, with no generated pointer commit:** Task 2.
- **Direct-only initialization and nested-submodule protection:** Task 3.
- **Changed-gitlink staging, exact commit subject, unrelated staged-file isolation:** Task 3.
- **`--no-commit`, already-current success, status reporting, final repository gates:** Task 3.
