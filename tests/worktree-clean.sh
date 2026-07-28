#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMMAND="$ROOT/bin/worktree-clean"

WORK=""
cleanup() {
  [ -n "$WORK" ] && rm -rf "$WORK"
}
trap cleanup EXIT

fail_test() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local output="$1" expected="$2" message="$3"
  case "$output" in
    *"$expected"*) ;;
    *) fail_test "$message: missing '$expected'" ;;
  esac
}

refute_contains() {
  local output="$1" unexpected="$2" message="$3"
  case "$output" in
    *"$unexpected"*) fail_test "$message: unexpected '$unexpected'" ;;
  esac
}

# One repository with four worktrees: clean+pushed, dirty, unpushed, and clean
# at the superproject but holding an unpushed submodule branch.
build_fixture() {
  # Resolve symlinks (macOS /var → /private/var) so paths match the report.
  WORK="$(cd "$(mktemp -d)" && pwd -P)"
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
  export GIT_ALLOW_PROTOCOL=file

  git init -q --bare "$WORK/remote.git" -b main
  git clone -q "$WORK/remote.git" "$WORK/repo" 2>/dev/null
  git -C "$WORK/repo" config protocol.file.allow always
  git -C "$WORK/repo" commit -q --allow-empty -m init
  git -C "$WORK/repo" push -q origin main

  git -C "$WORK/repo" worktree add -q worktrees/clean -b clean
  git -C "$WORK/repo" push -q origin clean

  git -C "$WORK/repo" worktree add -q worktrees/dirty -b dirty
  git -C "$WORK/repo" push -q origin dirty
  printf 'scratch\n' > "$WORK/repo/worktrees/dirty/scratch.txt"

  git -C "$WORK/repo" worktree add -q worktrees/unpushed -b unpushed
  git -C "$WORK/repo/worktrees/unpushed" commit -q --allow-empty -m "local only"

  git init -q --bare "$WORK/subremote.git" -b main
  git clone -q "$WORK/subremote.git" "$WORK/sub" 2>/dev/null
  git -C "$WORK/sub" commit -q --allow-empty -m init
  git -C "$WORK/sub" push -q origin main
  git -C "$WORK/repo" submodule add -q "$WORK/subremote.git" sub
  git -C "$WORK/repo" commit -qm "add submodule"
  git -C "$WORK/repo" push -q origin main
  git -C "$WORK/repo" worktree add -q worktrees/subwork -b subwork
  git -C "$WORK/repo/worktrees/subwork" submodule update --init -q
  git -C "$WORK/repo/worktrees/subwork" push -q origin subwork
  git -C "$WORK/repo/worktrees/subwork/sub" switch -qc subwork
  git -C "$WORK/repo/worktrees/subwork/sub" commit -q --allow-empty -m "unpushed"
  git -C "$WORK/repo/worktrees/subwork" commit -qm "bump gitlink" -- sub
  git -C "$WORK/repo/worktrees/subwork" push -q origin subwork

  # A worktree created *inside* a submodule: its .git is a file, so a
  # directory-only scan never reaches it.
  git -C "$WORK/repo" submodule update --init -q
  git -C "$WORK/repo/sub" worktree add -q worktrees/nested -b nested
  git -C "$WORK/repo/sub" push -q origin nested
}

test_reaches_worktrees_inside_submodules() {
  local output
  output="$("$COMMAND" --dry-run --root "$WORK")"
  assert_contains "$output" "$WORK/repo/sub/worktrees/nested" \
    "submodule worktree is discovered"
}

test_dry_run_keeps_everything() {
  local output
  output="$("$COMMAND" --dry-run --root "$WORK")"
  assert_contains "$output" "[dry-run] $WORK/repo/worktrees/clean" "clean is removable"
  assert_contains "$output" "Dry run only" "dry-run footer"
  [ -d "$WORK/repo/worktrees/clean" ] || fail_test "dry run deleted a worktree"
}

test_keeps_unsafe_worktrees() {
  local output
  output="$("$COMMAND" --root "$WORK")"
  assert_contains "$output" "uncommitted changes" "dirty worktree is kept"
  assert_contains "$output" "unpushed commits" "unpushed worktree is kept"
  assert_contains "$output" "unpushed commits in sub" "unpushed submodule branch is kept"
  refute_contains "$output" "[rm] $WORK/repo/worktrees/dirty" "dirty worktree removed"

  [ -d "$WORK/repo/worktrees/clean" ] && fail_test "clean worktree was not removed"
  [ -d "$WORK/repo/worktrees/dirty" ] || fail_test "dirty worktree was removed"
  [ -d "$WORK/repo/worktrees/subwork" ] || fail_test "submodule worktree was removed"
  [ -d "$WORK/repo/worktrees/unpushed" ] || fail_test "unpushed worktree was removed"
}

test_second_run_is_idempotent() {
  local output
  output="$("$COMMAND" --root "$WORK")"
  assert_contains "$output" "0 removed" "nothing left to remove"
}

test_force_removes_everything() {
  local output
  output="$("$COMMAND" --force --root "$WORK")"
  assert_contains "$output" "forced over" "force annotates the reason"
  [ -d "$WORK/repo/worktrees/dirty" ] && fail_test "force left a worktree behind"

  output="$(git -C "$WORK/repo" worktree list)"
  refute_contains "$output" "worktrees/" "registry still lists removed worktrees"
  output="$(git -C "$WORK/repo" branch --format='%(refname:short)')"
  assert_contains "$output" "unpushed" "force must not delete branches"
}

test_rejects_bad_arguments() {
  if "$COMMAND" --root "$WORK/does-not-exist" >/dev/null 2>&1; then
    fail_test "missing root was accepted"
  fi
  if "$COMMAND" --bogus >/dev/null 2>&1; then
    fail_test "unknown argument was accepted"
  fi
}

build_fixture
test_reaches_worktrees_inside_submodules
printf 'ok 1 - recurses into worktrees inside submodules\n'
test_dry_run_keeps_everything
printf 'ok 2 - dry run reports without deleting\n'
test_keeps_unsafe_worktrees
printf 'ok 3 - keeps dirty, unpushed, and unpushed-submodule worktrees\n'
test_second_run_is_idempotent
printf 'ok 4 - repeated runs are idempotent\n'
test_force_removes_everything
printf 'ok 5 - force removes worktrees but keeps branches\n'
test_rejects_bad_arguments
printf 'ok 6 - rejects invalid arguments\n'
printf '1..6\n'
