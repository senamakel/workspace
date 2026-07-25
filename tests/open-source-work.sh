#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMMAND="$ROOT/bin/open-source-work"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/open-source/issues" "$TEST_ROOT/target/.git"
jq -n \
  --slurpfile repository "$ROOT/tests/fixtures/open-source-repository.json" \
  '{
    schema_version: 1,
    updated_at: "2026-07-25T12:00:00Z",
    repositories: $repository
  }' >"$TEST_ROOT/open-source/repositories.json"
jq '
  .claim = {
    "worker": "test/deepcode-flash",
    "claimed_at": "2026-07-25T13:00:00Z",
    "branch": "fix-42",
    "worktree": $worktree
  }
  | .status = "claimed"
  | .history += [{
      "at": "2026-07-25T13:00:00Z",
      "status": "claimed",
      "note": "Claimed for helper tests."
    }]
' --arg worktree "$TEST_ROOT/target" \
  "$ROOT/tests/fixtures/open-source-queued-issue.json" \
  >"$TEST_ROOT/open-source/issues/example--project--42.json"

run_command() {
  OPEN_SOURCE_CONTROL_ROOT="$TEST_ROOT" "$COMMAND" "$@"
}

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

test_lists_active_repositories() {
  local output
  output="$(run_command repos)"
  assert_contains "$output" "example/project" "active repository"
  assert_contains "$output" $'REPOSITORY\tBRANCH' "repository headings"
}

test_lists_and_resolves_claims() {
  local output
  output="$(run_command queue --status claimed)"
  assert_contains "$output" "example/project#42" "claimed issue"
  [ "$(run_command path 'example/project#42')" = "$TEST_ROOT/target" ] \
    || fail_test "claim path was not resolved"
  [ "$(run_command show 'example/project#42' | jq -r .title)" = \
    "Handle an empty configuration file" ] \
    || fail_test "issue details were not returned"
}

test_runs_inside_target() {
  local output
  output="$(run_command run 'example/project#42' -- pwd -P)"
  [ "$output" = "$TEST_ROOT/target" ] \
    || fail_test "command did not run inside the target"
}

test_rejects_unknown_issue() {
  if run_command show 'example/project#99' >/dev/null 2>&1; then
    fail_test "unknown issue was accepted"
  fi
}

test_lists_active_repositories
printf 'ok 1 - lists active repositories\n'
test_lists_and_resolves_claims
printf 'ok 2 - lists and resolves claimed issues\n'
test_runs_inside_target
printf 'ok 3 - runs commands inside the target repository\n'
test_rejects_unknown_issue
printf 'ok 4 - rejects unknown issues\n'
printf '1..4\n'
