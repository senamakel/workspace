#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMMAND="$ROOT/bin/open-source-agent"

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

test_routes_research() {
  local output
  output="$("$COMMAND" research codex --limit 3 --dry-run)"
  assert_contains "$output" "You discover open-source GitHub repositories" \
    "research playbook"
  assert_contains "$output" "Batch limit: 3" "research limit"
  assert_contains "$output" "Harness: codex" "research harness"
}

test_routes_contributor() {
  local output
  output="$("$COMMAND" contribute --limit 2 --dry-run "resume waiting PRs")"
  assert_contains "$output" "You are the master execution agent" \
    "contributor playbook"
  assert_contains "$output" "Batch limit: 2" "contributor limit"
  assert_contains "$output" "Harness: deepcode" \
    "default contributor harness"
  assert_contains "$output" "Additional instructions: resume waiting PRs" \
    "contributor extra prompt"
}

test_rejects_bad_limit() {
  if "$COMMAND" triage --limit 0 --dry-run >/dev/null 2>&1; then
    fail_test "zero limit was accepted"
  fi
  if "$COMMAND" triage --limit 51 --dry-run >/dev/null 2>&1; then
    fail_test "limit above the hard cap was accepted"
  fi
}

test_routes_research
printf 'ok 1 - routes repository research\n'
test_routes_contributor
printf 'ok 2 - routes master contribution work\n'
test_rejects_bad_limit
printf 'ok 3 - rejects invalid batch limits\n'
printf '1..3\n'
