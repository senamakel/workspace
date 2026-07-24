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

run_test "validates the command interface" test_interface_validation
run_test "does not synchronize the superproject" test_superproject_is_not_synchronized
run_test "prefers upstream main and forces local main" test_prefers_upstream_and_forces_local_main
run_test "falls back to origin for every unusable upstream condition" test_origin_fallback_conditions
run_test "fails when neither remote exposes main" test_fails_without_remote_main
run_test "fails without overwriting an untracked obstruction" test_fails_without_overwriting_untracked_obstruction
printf '1..%s\n' "$PASS_COUNT"
