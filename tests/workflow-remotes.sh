#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMMAND="$ROOT/bin/workflow-remotes"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/workflow-remotes-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail_test() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [ "$expected" = "$actual" ] \
    || fail_test "$message: expected '$expected', got '$actual'"
}

configure_identity() {
  git -C "$1" config user.name "Workflow Remotes Test"
  git -C "$1" config user.email "workflow-remotes@example.invalid"
}

make_repo() {
  local path="$1" name="$2"
  git init -q "$path"
  configure_identity "$path"
  printf '%s\n' "$name" > "$path/state.txt"
  git -C "$path" add state.txt
  git -C "$path" commit -qm "Initialize $name"
  git -C "$path" branch -M main
}

make_fixture() {
  local suffix="$1"
  local nested="$TEST_ROOT/$suffix-nested"
  local direct="$TEST_ROOT/$suffix-direct"
  local workflow="$TEST_ROOT/$suffix-workflow-openhuman"

  make_repo "$nested" backend
  git -C "$nested" remote add origin git@github.com:tinyhumansai/backend.git

  make_repo "$direct" openhuman
  GIT_ALLOW_PROTOCOL=file git -C "$direct" submodule add -q \
    "$nested" modules/backend
  git -C "$direct" commit -qm "Add nested backend"
  git -C "$direct" remote add origin git@github.com:tinyhumansai/openhuman.git

  make_repo "$workflow" workflow-openhuman
  GIT_ALLOW_PROTOCOL=file git -C "$workflow" submodule add -q \
    "$direct" modules/openhuman
  git -C "$workflow" commit -qm "Add direct openhuman"
  git -C "$workflow" remote add origin \
    git@github.com:tinyhumansai/workflow-openhuman.git

  GIT_ALLOW_PROTOCOL=file git -C "$workflow" submodule update -q --init --recursive
  git -C "$workflow/modules/openhuman" remote set-url origin \
    git@github.com:tinyhumansai/openhuman.git
  git -C "$workflow/modules/openhuman/modules/backend" remote set-url origin \
    git@github.com:tinyhumansai/backend.git
  printf '%s\n' "$workflow"
}

assert_repository_config() {
  local directory="$1" repository="$2" origin_owner="$3"
  assert_eq "git@github.com:$origin_owner/$repository.git" \
    "$(git -C "$directory" remote get-url origin)" \
    "$directory origin"
  assert_eq "git@github.com:tinyhumansai/$repository.git" \
    "$(git -C "$directory" remote get-url upstream)" \
    "$directory upstream"
  assert_eq origin "$(git -C "$directory" config remote.pushDefault)" \
    "$directory push default"
  assert_eq upstream "$(git -C "$directory" config branch.main.remote)" \
    "$directory main pull remote"
  assert_eq refs/heads/main \
    "$(git -C "$directory" config branch.main.merge)" \
    "$directory main pull branch"
}

test_configures_recursive_remotes_idempotently() {
  local workflow before after
  workflow="$(make_fixture configured)"

  GIT_ALLOW_PROTOCOL=file "$COMMAND" "$workflow" >/dev/null

  assert_repository_config "$workflow" workflow-openhuman tinyhumansai
  assert_repository_config "$workflow/modules/openhuman" openhuman senamakel
  assert_repository_config \
    "$workflow/modules/openhuman/modules/backend" backend senamakel

  before="$(
    git -C "$workflow" config --local --list
    git -C "$workflow/modules/openhuman" config --local --list
    git -C "$workflow/modules/openhuman/modules/backend" config --local --list
  )"
  GIT_ALLOW_PROTOCOL=file "$COMMAND" "$workflow" >/dev/null
  after="$(
    git -C "$workflow" config --local --list
    git -C "$workflow/modules/openhuman" config --local --list
    git -C "$workflow/modules/openhuman/modules/backend" config --local --list
  )"
  assert_eq "$before" "$after" "second run is idempotent"
}

test_dry_run_is_inert() {
  local workflow before after output
  workflow="$(make_fixture dry-run)"
  before="$(
    git -C "$workflow" config --local --list
    git -C "$workflow/modules/openhuman" config --local --list
  )"

  output="$("$COMMAND" --dry-run "$workflow")"

  after="$(
    git -C "$workflow" config --local --list
    git -C "$workflow/modules/openhuman" config --local --list
  )"
  assert_eq "$before" "$after" "dry-run leaves configuration unchanged"
  case "$output" in
    *"[would configure]"*) ;;
    *) fail_test "dry-run does not report configuration" ;;
  esac
}

test_configures_recursive_remotes_idempotently
printf 'ok 1 - configures root and recursive submodule remotes idempotently\n'
test_dry_run_is_inert
printf 'ok 2 - keeps dry-run inert\n'
printf '1..2\n'
