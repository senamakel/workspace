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

test_prefers_upstream_and_forces_local_main() {
  local origin upstream super selected local_commit output
  origin="$(make_remote preference-origin)"
  upstream="$(make_remote preference-upstream)"
  super="$(make_superproject_with_submodule preference-super "$origin")"
  git -C "$super/modules/alpha" remote add upstream "$upstream"
  advance_remote preference-origin "origin tip" >/dev/null
  selected="$(advance_remote preference-upstream "upstream tip")"

  printf 'unpushed local commit\n' > "$super/modules/alpha/state.txt"
  git -C "$super/modules/alpha" add state.txt
  git -C "$super/modules/alpha" commit -qm "Unpushed local commit"
  local_commit="$(git -C "$super/modules/alpha" rev-parse HEAD)"
  git -C "$super/modules/alpha" checkout -qb divergent
  printf 'tracked dirt\n' > "$super/modules/alpha/state.txt"
  printf 'preserve me\n' > "$super/modules/alpha/untracked.txt"

  output="$(cd "$super/modules" && GIT_ALLOW_PROTOCOL=file "$COMMAND" --no-commit 2>&1)"

  assert_eq "main" "$(git -C "$super/modules/alpha" branch --show-current)" "submodule ends on local main"
  assert_eq "$selected" "$(git -C "$super/modules/alpha" rev-parse HEAD)" "upstream main is selected"
  assert_eq "$selected" "$(git -C "$super/modules/alpha" rev-parse refs/heads/main)" "local main is forced"
  [ "$local_commit" != "$(git -C "$super/modules/alpha" rev-parse refs/heads/main)" ] \
    || fail_test "unpushed local main commit was not discarded"
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

test_fails_without_overwriting_untracked_obstruction() {
  local origin super before status output
  origin="$(make_remote untracked-obstruction-origin)"
  super="$(make_superproject_with_submodule untracked-obstruction-super "$origin")"
  printf 'remote tracked content\n' > "$TEST_ROOT/untracked-obstruction-origin-seed/obstruction.txt"
  git -C "$TEST_ROOT/untracked-obstruction-origin-seed" add obstruction.txt
  git -C "$TEST_ROOT/untracked-obstruction-origin-seed" commit -qm "Add obstructing tracked file"
  git -C "$TEST_ROOT/untracked-obstruction-origin-seed" push -q origin main
  printf 'preserve local content\n' > "$super/modules/alpha/obstruction.txt"
  before="$(git -C "$super" rev-parse HEAD)"

  set +e
  output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" 2>&1)"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail_test "untracked obstruction must fail"
  assert_contains "$output" "untracked path obstructs synchronization: obstruction.txt" \
    "failure identifies the untracked obstruction"
  assert_eq "preserve local content" "$(cat "$super/modules/alpha/obstruction.txt")" \
    "untracked obstruction content is preserved"
  assert_eq "$before" "$(git -C "$super" rev-parse HEAD)" \
    "untracked obstruction creates no pointer commit"
}

test_commits_only_changed_direct_gitlinks() {
  local origin super selected before output committed_paths staged_paths
  origin="$(make_remote commit-mode-origin)"
  super="$(make_superproject_with_submodule commit-mode-super "$origin")"
  selected="$(advance_remote commit-mode-origin "commit mode tip")"
  printf 'keep staged\n' > "$super/unrelated.txt"
  git -C "$super" add unrelated.txt
  before="$(git -C "$super" rev-parse HEAD)"

  output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" 2>&1)"

  assert_eq "1" "$(git -C "$super" rev-list --count "$before..HEAD")" \
    "normal mode creates exactly one commit"
  assert_eq "Update submodule pointers" "$(git -C "$super" log -1 --format=%s)" \
    "pointer commit has the exact subject"
  assert_eq "$selected" "$(git -C "$super" rev-parse HEAD:modules/alpha)" \
    "pointer commit records the selected gitlink"
  committed_paths="$(git -C "$super" diff-tree --no-commit-id --name-only -r HEAD)"
  assert_eq "modules/alpha" "$committed_paths" \
    "pointer commit contains only the changed direct gitlink"
  staged_paths="$(git -C "$super" diff --cached --name-only)"
  assert_eq "unrelated.txt" "$staged_paths" \
    "unrelated pre-staged file remains staged"
  assert_contains "$output" "committed submodule pointer update" \
    "normal mode reports the pointer commit"
}

test_no_commit_and_already_current_modes() {
  local origin super selected before output staged_paths current
  origin="$(make_remote no-commit-origin)"
  super="$(make_superproject_with_submodule no-commit-super "$origin")"
  selected="$(advance_remote no-commit-origin "no commit tip")"
  before="$(git -C "$super" rev-parse HEAD)"

  output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" --no-commit 2>&1)"

  assert_eq "$before" "$(git -C "$super" rev-parse HEAD)" \
    "--no-commit preserves superproject HEAD"
  staged_paths="$(git -C "$super" diff --cached --name-only)"
  assert_eq "modules/alpha" "$staged_paths" \
    "--no-commit stages the selected direct gitlink"
  assert_eq "$selected" "$(git -C "$super" rev-parse :modules/alpha)" \
    "the staged gitlink records the selected commit"
  assert_contains "$output" "pointer changes staged; commit skipped (--no-commit)" \
    "--no-commit reports the skipped commit"

  git -C "$super" commit -qm "Record alpha pointer" -- modules/alpha
  current="$(git -C "$super" rev-parse HEAD)"
  output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" 2>&1)"

  assert_eq "$current" "$(git -C "$super" rev-parse HEAD)" \
    "already-current mode creates no commit"
  assert_contains "$output" "all submodule pointers already up to date" \
    "already-current mode reports up to date"
}

test_initializes_uninitialized_direct_submodule() {
  local origin super selected output staged_paths
  origin="$(make_remote uninitialized-direct-origin)"
  super="$(make_superproject_with_submodule uninitialized-direct-super "$origin")"
  selected="$(advance_remote uninitialized-direct-origin "initialized direct tip")"

  git -C "$super" submodule deinit -f -- modules/alpha
  rmdir "$super/modules/alpha"
  assert_file_missing "$super/modules/alpha" \
    "direct submodule checkout starts removed"

  output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" --no-commit 2>&1)"

  [ -f "$super/modules/alpha/.git" ] \
    || fail_test "direct submodule was not initialized"
  assert_eq "main" "$(git -C "$super/modules/alpha" branch --show-current)" \
    "initialized direct submodule ends on local main"
  assert_eq "$selected" "$(git -C "$super/modules/alpha" rev-parse HEAD)" \
    "initialized direct submodule reaches selected origin main"
  staged_paths="$(git -C "$super" diff --cached --name-only)"
  assert_eq "modules/alpha" "$staged_paths" \
    "--no-commit stages the initialized direct gitlink"
  assert_eq "$selected" "$(git -C "$super" rev-parse :modules/alpha)" \
    "staged direct gitlink records the selected commit"
  assert_contains "$output" "modules/alpha: selected origin/$selected" \
    "status identifies the selected direct-submodule commit"
}

test_supports_old_form_direct_submodule() {
  local origin super submodule git_dir selected output status staged_paths
  origin="$(make_remote old-form-origin)"
  super="$(make_superproject_with_submodule old-form-super "$origin")"
  submodule="$super/modules/alpha"
  git_dir="$(git -C "$submodule" rev-parse --absolute-git-dir)"

  git -C "$submodule" config --unset core.worktree
  rm "$submodule/.git"
  mv "$git_dir" "$submodule/.git"
  selected="$(advance_remote old-form-origin "old form tip")"

  set +e
  output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" --no-commit 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "old-form direct-submodule update succeeds: $output"
  assert_eq "main" "$(git -C "$submodule" branch --show-current)" \
    "old-form submodule ends on local main"
  assert_eq "$selected" "$(git -C "$submodule" rev-parse HEAD)" \
    "old-form submodule reaches selected origin main"
  assert_eq "$selected" "$(git -C "$submodule" rev-parse refs/heads/main)" \
    "old-form local main is forced to the selected commit"
  staged_paths="$(git -C "$super" diff --cached --name-only)"
  assert_eq "modules/alpha" "$staged_paths" \
    "--no-commit stages the old-form direct gitlink"
  assert_eq "$selected" "$(git -C "$super" rev-parse :modules/alpha)" \
    "staged old-form gitlink records the selected commit"
  assert_contains "$output" "modules/alpha: selected origin/$selected" \
    "status identifies the selected old-form direct-submodule commit"
}

test_supports_spaced_submodule_names_and_paths() {
  local origin super selected output staged_paths status
  origin="$(make_remote spaced-path-origin)"
  super="$TEST_ROOT/spaced-path-super"

  git init -q "$super"
  configure_identity "$super"
  git -c protocol.file.allow=always -C "$super" \
    submodule add -q "$origin" "modules/alpha beta"
  git -C "$super" commit -qm "Add spaced-path submodule"
  selected="$(advance_remote spaced-path-origin "spaced path tip")"

  set +e
  output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" --no-commit 2>&1)"
  status=$?
  set -e

  assert_eq "0" "$status" "spaced-path update succeeds: $output"
  assert_eq "main" "$(git -C "$super/modules/alpha beta" branch --show-current)" \
    "spaced-path submodule ends on local main"
  assert_eq "$selected" "$(git -C "$super/modules/alpha beta" rev-parse HEAD)" \
    "spaced-path submodule reaches selected origin main"
  assert_eq "$selected" "$(git -C "$super/modules/alpha beta" rev-parse refs/heads/main)" \
    "spaced-path local main is forced to the selected commit"
  staged_paths="$(git -C "$super" diff --cached --name-only)"
  assert_eq "modules/alpha beta" "$staged_paths" \
    "--no-commit stages the spaced direct gitlink"
  assert_eq "$selected" "$(git -C "$super" rev-parse ':modules/alpha beta')" \
    "staged spaced gitlink records the selected commit"
  assert_contains "$output" "modules/alpha beta: selected origin/$selected" \
    "status preserves the complete spaced submodule path"
}

test_rejects_unrelated_repository_at_submodule_path() {
  local origin super unrelated_head unrelated_branch unrelated_content
  local super_head super_gitlink output status
  origin="$(make_remote unrelated-repository-origin)"
  super="$(make_superproject_with_submodule unrelated-repository-super "$origin")"

  git -C "$super" submodule deinit -f -- modules/alpha
  rmdir "$super/modules/alpha"
  git init -q "$super/modules/alpha"
  configure_identity "$super/modules/alpha"
  git -C "$super/modules/alpha" remote add origin "$origin"
  printf 'valuable local content\n' > "$super/modules/alpha/valuable.txt"
  git -C "$super/modules/alpha" add valuable.txt
  git -C "$super/modules/alpha" commit -qm "Valuable unrelated commit"
  git -C "$super/modules/alpha" branch -M main

  unrelated_head="$(git -C "$super/modules/alpha" rev-parse HEAD)"
  unrelated_branch="$(git -C "$super/modules/alpha" branch --show-current)"
  unrelated_content="$(cat "$super/modules/alpha/valuable.txt")"
  super_head="$(git -C "$super" rev-parse HEAD)"
  super_gitlink="$(git -C "$super" rev-parse :modules/alpha)"

  set +e
  output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" --no-commit 2>&1)"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail_test "unrelated repository at submodule path must fail"
  assert_contains "$output" \
    "modules/alpha: unrelated Git repository obstructs submodule path" \
    "failure identifies the unrelated repository obstruction"
  assert_eq "$unrelated_head" "$(git -C "$super/modules/alpha" rev-parse HEAD)" \
    "unrelated repository HEAD is unchanged"
  assert_eq "$unrelated_branch" "$(git -C "$super/modules/alpha" branch --show-current)" \
    "unrelated repository branch is unchanged"
  assert_eq "$unrelated_content" "$(cat "$super/modules/alpha/valuable.txt")" \
    "unrelated repository tracked content is unchanged"
  assert_eq "$super_head" "$(git -C "$super" rev-parse HEAD)" \
    "unrelated repository obstruction preserves superproject HEAD"
  assert_eq "$super_gitlink" "$(git -C "$super" rev-parse :modules/alpha)" \
    "unrelated repository obstruction preserves the staged gitlink"
}

test_does_not_initialize_nested_submodules() {
  local nested parent super output
  nested="$(make_remote nested-child)"
  parent="$(make_remote nested-parent)"
  git -c protocol.file.allow=always -C "$TEST_ROOT/nested-parent-seed" \
    submodule add -q "$nested" nested/child
  git -C "$TEST_ROOT/nested-parent-seed" commit -qm "Add nested child submodule"
  git -C "$TEST_ROOT/nested-parent-seed" push -q origin main
  super="$(make_superproject_with_submodule nested-super "$parent")"

  assert_file_missing "$super/modules/alpha/nested/child/.git" \
    "nested submodule starts uninitialized"
  output="$(cd "$super" && GIT_ALLOW_PROTOCOL=file "$COMMAND" --no-commit 2>&1)"

  assert_file_missing "$super/modules/alpha/nested/child/.git" \
    "workflow update leaves the nested submodule uninitialized"
  assert_contains "$output" "modules/alpha: selected origin/" \
    "direct parent submodule is still processed"
}

run_test "validates the command interface" test_interface_validation
run_test "does not synchronize the superproject" test_superproject_is_not_synchronized
run_test "prefers upstream main and forces local main" test_prefers_upstream_and_forces_local_main
run_test "falls back to origin for every unusable upstream condition" test_origin_fallback_conditions
run_test "fails when neither remote exposes main" test_fails_without_remote_main
run_test "fails without overwriting an untracked obstruction" test_fails_without_overwriting_untracked_obstruction
run_test "commits only changed direct gitlinks" test_commits_only_changed_direct_gitlinks
run_test "supports no-commit and already-current modes" test_no_commit_and_already_current_modes
run_test "initializes an uninitialized direct submodule" test_initializes_uninitialized_direct_submodule
run_test "supports an old-form direct submodule" test_supports_old_form_direct_submodule
run_test "supports spaced submodule names and paths" test_supports_spaced_submodule_names_and_paths
run_test "rejects an unrelated repository at a submodule path" test_rejects_unrelated_repository_at_submodule_path
run_test "does not initialize nested submodules" test_does_not_initialize_nested_submodules
printf '1..%s\n' "$PASS_COUNT"
