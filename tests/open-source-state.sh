#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECK="$ROOT/bin/check-open-source-state"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/open-source-state-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail_test() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

make_state() {
  local path="$1"
  mkdir -p "$path/issues"
  cp "$ROOT/open-source/repositories.json" "$path/repositories.json"
}

test_empty_state_is_valid() {
  local state="$TEST_ROOT/empty"
  make_state "$state"
  "$CHECK" "$state" >/dev/null
}

test_valid_queued_issue_is_accepted() {
  local state="$TEST_ROOT/valid"
  make_state "$state"
  cp "$ROOT/tests/fixtures/open-source-queued-issue.json" \
    "$state/issues/example--project--42.json"
  "$CHECK" "$state" >/dev/null
}

test_active_pr_is_rejected() {
  local state="$TEST_ROOT/active-pr"
  make_state "$state"
  jq '.signals.has_active_pr = true' \
    "$ROOT/tests/fixtures/open-source-queued-issue.json" \
    >"$state/issues/example--project--42.json"
  if "$CHECK" "$state" >/dev/null 2>&1; then
    fail_test "issue with an active PR passed validation"
  fi
}

test_empty_state_is_valid
printf 'ok 1 - accepts an empty catalog and queue\n'
test_valid_queued_issue_is_accepted
printf 'ok 2 - accepts a complete queued issue\n'
test_active_pr_is_rejected
printf 'ok 3 - rejects an issue with an active PR\n'
printf '1..3\n'
