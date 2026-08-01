#!/usr/bin/env bash
# Exercises commit-critic's offline logic — thresholds, verdict parsing, hook
# event filtering, the loop guard, and its refusal to fail a commit when the
# summarizer is unavailable — against a stubbed CLI and no credentials.
set -euo pipefail

COMMAND="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/bin/commit-critic"
PASS_COUNT=0
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/commit-critic-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail_test() { printf 'not ok - %s\n' "$*" >&2; exit 1; }

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [ "$actual" = "$expected" ] || fail_test "$message: expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail_test "$message: missing '$needle' in '$haystack'" ;;
  esac
}

run_test() {
  local name="$1"
  shift
  "$@"
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s - %s\n' "$PASS_COUNT" "$name"
}

# A repository with one commit of the requested shape.
make_repo() {
  local name="$1" files="$2" lines="$3"
  local repo="$TEST_ROOT/$name"
  local i j
  # Every Git call is silenced: this function's stdout is the repository path
  # and nothing else, so a stray "nothing to commit" cannot end up being cd'd to.
  rm -rf "$repo"
  mkdir -p "$repo"
  {
    git -C "$repo" init -q
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name "Test"
    git -C "$repo" commit -q --allow-empty -m "Base"
  } >/dev/null 2>&1
  for i in $(seq 1 "$files"); do
    : > "$repo/file$i.txt"
    for j in $(seq 1 "$lines"); do printf 'line %s\n' "$j" >> "$repo/file$i.txt"; done
  done
  git -C "$repo" add -A >/dev/null 2>&1
  git -C "$repo" commit -q -m "Add $files file(s)" >/dev/null 2>&1
  printf '%s\n' "$repo"
}

# A stub standing in for deepcode-flash: prints whatever verdict it was built
# with, so no network or credential is involved.
make_stub() {
  local name="$1" body="$2" stub="$TEST_ROOT/stub-$name"
  mkdir -p "$stub"
  cat > "$stub/critic" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$body"
EOF
  chmod +x "$stub/critic"
  printf '%s\n' "$stub/critic"
}

state_dir() { printf '%s/state-%s\n' "$TEST_ROOT" "$1"; }

test_small_commit_skips_the_model() {
  local repo output
  repo="$(make_repo small 1 5)"
  # A stub that would fail the test if it ran at all.
  output="$(cd "$repo" && COMMIT_CRITIC_CMD=/nonexistent-critic "$COMMAND")"
  assert_contains "$output" "[OK]" "small commit passes"
  assert_contains "$output" "below the split threshold" "small commit never calls the model"
}

test_large_single_purpose_commit_passes() {
  local repo stub output
  repo="$(make_repo okay 6 40)"
  stub="$(make_stub ok "VERDICT: ok
SUMMARY: adds six files of the same fixture")"
  output="$(cd "$repo" && COMMIT_CRITIC_CMD="$stub" "$COMMAND")"
  assert_contains "$output" "[OK]" "a large but coherent commit passes"
  assert_contains "$output" "same fixture" "the model summary is reported"
}

test_split_verdict_is_reported() {
  local repo stub output status
  repo="$(make_repo mixed 6 40)"
  stub="$(make_stub split "VERDICT: split
SUMMARY: bundles a parser fix and unrelated docs
REASON: the docs change is independent of the parser fix
SPLIT:
- parser: handle empty input -- parser.c
- docs: describe the parser -- README.md")"
  set +e
  output="$(cd "$repo" && COMMIT_CRITIC_CMD="$stub" "$COMMAND" 2>&1)"
  status=$?
  set -e
  assert_eq 0 "$status" "outside hook mode a split verdict still exits 0"
  assert_contains "$output" "[SPLIT]" "the split verdict is reported"
  assert_contains "$output" "parser: handle empty input" "the suggested split is shown"
}

test_json_output_carries_the_verdict() {
  local repo stub output
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo json 6 40)"
  stub="$(make_stub jsonok "VERDICT: ok
SUMMARY: one coherent change")"
  output="$(cd "$repo" && COMMIT_CRITIC_CMD="$stub" "$COMMAND" --json)"
  assert_eq "ok" "$(printf '%s' "$output" | jq -r .verdict)" "json reports the verdict"
  assert_eq "6" "$(printf '%s' "$output" | jq -r .files)" "json reports the file count"
}

test_unavailable_summarizer_never_fails() {
  local repo stub output status
  repo="$(make_repo unavailable 6 40)"
  stub="$(make_stub broken "")"
  cat > "$stub" <<'EOF'
#!/usr/bin/env bash
echo "no credential configured" >&2
exit 1
EOF
  chmod +x "$stub"
  set +e
  output="$(cd "$repo" && COMMIT_CRITIC_CMD="$stub" "$COMMAND" 2>&1)"
  status=$?
  set -e
  assert_eq 0 "$status" "an unreachable summarizer must not fail the commit"
  assert_contains "$output" "[SKIPPED]" "the skip is reported"
}

test_hook_ignores_non_commit_commands() {
  local repo stub status
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo hooknoncommit 6 40)"
  stub="$(make_stub hooknon "VERDICT: split
SUMMARY: would fail the test if it ran")"
  set +e
  printf '{"tool_input":{"command":"ls -la"},"tool_response":{"exit_code":0}}' \
    | (cd "$repo" && COMMIT_CRITIC_CMD="$stub" \
       XDG_STATE_HOME="$(state_dir hooknon)" "$COMMAND" --hook >/dev/null 2>&1)
  status=$?
  set -e
  assert_eq 0 "$status" "a non-commit Bash call is ignored"
}

test_hook_blocks_a_split_verdict() {
  local repo stub status err state
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo hookblock 6 40)"
  state="$(state_dir hookblock)"
  stub="$(make_stub hookblock "VERDICT: split
SUMMARY: bundles two concerns
REASON: the fix and the refactor are independent
SPLIT:
- fix: handle empty input -- parser.c")"
  set +e
  err="$(printf '{"tool_input":{"command":"git commit -m x"},"tool_response":{"exit_code":0}}' \
    | (cd "$repo" && COMMIT_CRITIC_CMD="$stub" XDG_STATE_HOME="$state" \
       "$COMMAND" --hook 2>&1 >/dev/null))"
  status=$?
  set -e
  assert_eq 2 "$status" "hook mode exits 2 so the harness is told to split"
  assert_contains "$err" "git reset --soft HEAD~1" "the unwind command is given"
  assert_contains "$err" "atomic-commit" "the repo's commit command is named"
}

test_hook_critiques_each_commit_once() {
  local repo stub state status
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo hookonce 6 40)"
  state="$(state_dir hookonce)"
  stub="$(make_stub hookonce "VERDICT: split
SUMMARY: bundles two concerns")"
  local event='{"tool_input":{"command":"git commit -m x"},"tool_response":{"exit_code":0}}'

  set +e
  printf '%s' "$event" | (cd "$repo" && COMMIT_CRITIC_CMD="$stub" \
    XDG_STATE_HOME="$state" "$COMMAND" --hook >/dev/null 2>&1)
  status=$?
  set -e
  assert_eq 2 "$status" "the first sighting of a commit is critiqued"

  # Splitting a commit re-runs the hook; without the guard the same SHA would be
  # rejected forever and the harness could never make progress.
  set +e
  printf '%s' "$event" | (cd "$repo" && COMMIT_CRITIC_CMD="$stub" \
    XDG_STATE_HOME="$state" "$COMMAND" --hook >/dev/null 2>&1)
  status=$?
  set -e
  assert_eq 0 "$status" "the same commit is not critiqued twice"
}

# Feeds one hook event and reports whether the critic engaged (2) or bowed out (0).
hook_status() {
  local repo="$1" stub="$2" state="$3" command="$4" status
  set +e
  jq -n --arg c "$command" '{tool_input: {command: $c}, tool_response: {exit_code: 0}}' \
    | (cd "$repo" && COMMIT_CRITIC_CMD="$stub" XDG_STATE_HOME="$state" \
       "$COMMAND" --hook >/dev/null 2>&1)
  status=$?
  set -e
  printf '%s\n' "$status"
}

test_hook_matches_only_real_commit_invocations() {
  local repo stub i n=0
  command -v jq >/dev/null 2>&1 || return 0
  stub="$(make_stub matching "VERDICT: split
SUMMARY: bundles two concerns")"

  # Mentioning a commit command is not running one. `grep -n atomic-commit
  # README.md` used to fire the hook, which then critiqued whatever HEAD was.
  local ignored=(
    'ls -la'
    'grep -n "^### .atomic-commit" README.md'
    'echo "run atomic-commit later"'
    'git log --format=%s | grep commit'
    'rg "git commit" docs/'
  )
  for i in "${ignored[@]}"; do
    n=$((n + 1))
    repo="$(make_repo "ignore-$n" 6 40)"
    assert_eq 0 "$(hook_status "$repo" "$stub" "$(state_dir "ign$n")" "$i")" \
      "must ignore: $i"
  done

  local matched=(
    'git commit -m "x"'
    'atomic-commit "scoped" -- a.txt'
    'cd /tmp/repo && git commit -m "x"'
    'git -C /tmp/repo commit -m "x"'
    'GIT_AUTHOR_NAME=x git commit -m "y"'
    '/usr/bin/git commit -m "x"'
  )
  for i in "${matched[@]}"; do
    n=$((n + 1))
    repo="$(make_repo "match-$n" 6 40)"
    assert_eq 2 "$(hook_status "$repo" "$stub" "$(state_dir "mat$n")" "$i")" \
      "must match: $i"
  done
}

test_hook_ignores_a_commit_it_did_not_just_make() {
  local repo stub state status
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo stale 6 40)"
  state="$(state_dir stale)"
  stub="$(make_stub stale "VERDICT: split
SUMMARY: would fail the test if it ran")"
  # Backdate HEAD: a matched command that produced no commit (a dry run, an
  # empty commit, a commit in another repository) must not put someone else's
  # existing work under review.
  GIT_COMMITTER_DATE="2020-01-01T00:00:00" git -C "$repo" commit -q --amend --no-edit --date "2020-01-01T00:00:00"
  status="$(hook_status "$repo" "$stub" "$state" 'git commit -m "x"')"
  assert_eq 0 "$status" "an older commit is not the one the call just made"
}

test_hook_ignores_a_failed_commit() {
  local repo stub state status
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo hookfailed 6 40)"
  state="$(state_dir hookfailed)"
  stub="$(make_stub hookfailed "VERDICT: split
SUMMARY: would fail the test if it ran")"
  set +e
  printf '{"tool_input":{"command":"git commit -m x"},"tool_response":{"exit_code":1}}' \
    | (cd "$repo" && COMMIT_CRITIC_CMD="$stub" XDG_STATE_HOME="$state" \
       "$COMMAND" --hook >/dev/null 2>&1)
  status=$?
  set -e
  assert_eq 0 "$status" "a commit that failed leaves nothing to critique"
}

test_disabled_by_environment() {
  local repo stub status
  repo="$(make_repo disabled 6 40)"
  stub="$(make_stub disabled "VERDICT: split
SUMMARY: would fail the test if it ran")"
  set +e
  (cd "$repo" && COMMIT_CRITIC=0 COMMIT_CRITIC_CMD="$stub" "$COMMAND" >/dev/null 2>&1)
  status=$?
  set -e
  assert_eq 0 "$status" "COMMIT_CRITIC=0 disables the command"
}

run_test "small commits skip the model" test_small_commit_skips_the_model
run_test "a large single-purpose commit passes" test_large_single_purpose_commit_passes
run_test "a split verdict is reported" test_split_verdict_is_reported
run_test "json output carries the verdict" test_json_output_carries_the_verdict
run_test "an unavailable summarizer never fails a commit" test_unavailable_summarizer_never_fails
run_test "the hook ignores non-commit commands" test_hook_ignores_non_commit_commands
run_test "the hook blocks a split verdict" test_hook_blocks_a_split_verdict
run_test "the hook critiques each commit once" test_hook_critiques_each_commit_once
run_test "the hook matches only real commit invocations" test_hook_matches_only_real_commit_invocations
run_test "the hook ignores a commit it did not just make" test_hook_ignores_a_commit_it_did_not_just_make
run_test "the hook ignores a failed commit" test_hook_ignores_a_failed_commit
run_test "COMMIT_CRITIC=0 disables the command" test_disabled_by_environment
printf '1..%s\n' "$PASS_COUNT"
