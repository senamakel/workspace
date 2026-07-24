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
