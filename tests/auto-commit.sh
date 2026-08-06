#!/usr/bin/env bash
# Exercises auto-commit's offline logic — the tool-call counter, the repository
# allowlist, the detached-HEAD and in-progress-operation guards, credential
# filtering, message generation and its fallback, and the commit itself — with a
# stubbed model and no credentials.
set -euo pipefail

COMMAND="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/bin/auto-commit"
PASS_COUNT=0
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/auto-commit-test.XXXXXX")"
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

assert_not_contains() {
  local haystack="$1" needle="$2" message="$3"
  case "$haystack" in
    *"$needle"*) fail_test "$message: unexpected '$needle'" ;;
  esac
}

run_test() {
  local name="$1"
  shift
  "$@"
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s - %s\n' "$PASS_COUNT" "$name"
}

# A repository on a feature branch with one clean commit behind it.
make_repo() {
  local name="$1"
  local repo="$TEST_ROOT/$name"
  rm -rf "$repo"
  mkdir -p "$repo"
  {
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name "Test"
    # The command only runs in allowlisted repositories, so the fixture claims
    # one of them as its origin.
    git -C "$repo" remote add origin git@github.com:tinyhumansai/medulla.git
    printf 'base\n' > "$repo/base.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "Base"
    git -C "$repo" switch -q -c feature
  } >/dev/null 2>&1
  printf '%s\n' "$repo"
}

# Stands in for the model: prints a fixed subject, no network, no credential.
make_stub() {
  local name="$1" body="$2"
  local stub="$TEST_ROOT/stub-$name"
  cat > "$stub" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$body"
EOF
  chmod +x "$stub"
  printf '%s\n' "$stub"
}

state_dir() { printf '%s/state-%s\n' "$TEST_ROOT" "$1"; }

# Feeds one PostToolUse event.
fire() {
  local repo="$1" state="$2" stub="${3:-}"
  jq -n --arg s "session-fixed" '{session_id: $s, tool_name: "Bash", tool_input: {command: "ls"}}' \
    | (cd "$repo" && AUTO_COMMIT_CMD="$stub" XDG_STATE_HOME="$state" \
       "$COMMAND" --hook 2>&1)
}

# Feeds an event whose tool ran in a different checkout from the harness cwd.
fire_from() {
  local launch_repo="$1" work_repo="$2" state="$3" stub="${4:-}"
  jq -n --arg s "session-fixed" --arg workdir "$work_repo" \
    '{session_id: $s, cwd: $workdir, tool_name: "Bash", tool_input: {command: "ls", workdir: $workdir}}' \
    | (cd "$launch_repo" && AUTO_COMMIT_CMD="$stub" XDG_STATE_HOME="$state" \
       "$COMMAND" --hook 2>&1)
}

count_commits() { git -C "$1" rev-list --count HEAD; }

test_commits_on_every_tool_call_by_default() {
  local repo state stub before
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo default-cadence)"
  state="$(state_dir default-cadence)"
  stub="$(make_stub defaultcadence "chore: add a greeting")"
  before="$(count_commits "$repo")"

  # No AUTO_COMMIT_EVERY set: the default must checkpoint on the very first call.
  printf 'hello\n' > "$repo/new.txt"
  fire "$repo" "$state" "$stub" >/dev/null
  assert_eq "$((before + 1))" "$(count_commits "$repo")" "commits on the first tool call"

  printf 'more\n' >> "$repo/new.txt"
  fire "$repo" "$state" "$stub" >/dev/null
  assert_eq "$((before + 2))" "$(count_commits "$repo")" "commits again on the next call"

  # A call that changed nothing must not produce an empty commit.
  fire "$repo" "$state" "$stub" >/dev/null
  assert_eq "$((before + 2))" "$(count_commits "$repo")" "a clean tree adds no commit"
}

test_commits_the_tool_worktree_not_the_launch_checkout() {
  local launch_repo work_repo state stub before
  command -v jq >/dev/null 2>&1 || return 0
  launch_repo="$(make_repo launch-checkout)"
  work_repo="$(make_repo tool-worktree)"
  state="$(state_dir tool-worktree)"
  stub="$(make_stub toolworktree "chore: checkpoint the active worktree")"
  git -C "$launch_repo" switch -q main
  printf 'worktree change\n' > "$work_repo/new.txt"
  before="$(count_commits "$work_repo")"

  fire_from "$launch_repo" "$work_repo" "$state" "$stub" >/dev/null

  assert_eq "$((before + 1))" "$(count_commits "$work_repo")" \
    "the checkout named by the tool event is committed"
  assert_eq "" "$(git -C "$work_repo" status --porcelain)" \
    "the active worktree is clean afterwards"
  assert_eq 1 "$(count_commits "$launch_repo")" \
    "the launch checkout, which changed nothing, is untouched"
}

test_commits_only_every_nth_tool_call() {
  local repo state stub before
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo counter)"
  state="$(state_dir counter)"
  stub="$(make_stub counter "add a greeting")"
  printf 'hello\n' > "$repo/new.txt"
  before="$(count_commits "$repo")"

  AUTO_COMMIT_EVERY=3 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq "$before" "$(count_commits "$repo")" "no commit on the first tool call"
  AUTO_COMMIT_EVERY=3 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq "$before" "$(count_commits "$repo")" "no commit on the second tool call"
  AUTO_COMMIT_EVERY=3 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq "$((before + 1))" "$(count_commits "$repo")" "commits on the third tool call"

  # The counter resets, so the next commit is another three calls away.
  printf 'more\n' >> "$repo/new.txt"
  AUTO_COMMIT_EVERY=3 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq "$((before + 1))" "$(count_commits "$repo")" "counter restarts after a commit"
}

test_uses_the_generated_subject() {
  local repo state stub
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo subject)"
  state="$(state_dir subject)"
  stub="$(make_stub subject "add a greeting file")"
  printf 'hello\n' > "$repo/new.txt"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq "chore: add a greeting file" "$(git -C "$repo" log -1 --format=%s)" \
    "a non-conventional subject gets the fallback type"
}

test_keeps_a_conventional_subject_verbatim() {
  local repo state stub
  command -v jq >/dev/null 2>&1 || return 0
  for stub_subject in "feat: add a greeting file" "fix(parser): handle empty input" "refactor!: drop the old api"; do
    repo="$(make_repo "conv-$(printf '%s' "$stub_subject" | tr -cd 'a-z')")"
    state="$(state_dir "conv-$(printf '%s' "$stub_subject" | tr -cd 'a-z')")"
    stub="$(make_stub "conv$(printf '%s' "$stub_subject" | tr -cd 'a-z')" "$stub_subject")"
    printf 'hello\n' > "$repo/new.txt"
    AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
    assert_eq "$stub_subject" "$(git -C "$repo" log -1 --format=%s)" \
      "an already-conventional subject is not re-prefixed"
  done
}

test_commits_a_description_body() {
  local repo state stub body
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo body)"
  state="$(state_dir body)"
  stub="$(make_stub body "feat: add a greeting

- adds new.txt with a greeting
- second bullet describing the change")"
  printf 'hello\n' > "$repo/new.txt"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null

  assert_eq "feat: add a greeting" "$(git -C "$repo" log -1 --format=%s)" \
    "the subject is the first line only"
  body="$(git -C "$repo" log -1 --format=%b)"
  assert_contains "$body" "adds new.txt with a greeting" "the first bullet is committed"
  assert_contains "$body" "second bullet" "the second bullet is committed"
  assert_not_contains "$(git -C "$repo" log -1 --format=%s)" "adds new.txt" \
    "body content does not leak into the subject"
}

test_subject_only_reply_still_commits() {
  local repo state stub
  command -v jq >/dev/null 2>&1 || return 0
  # A model that returns no bullets must not abort the commit — grep filtering an
  # empty body away used to kill the script under pipefail.
  repo="$(make_repo nobody)"
  state="$(state_dir nobody)"
  stub="$(make_stub nobody "fix: handle empty input")"
  printf 'hello\n' > "$repo/new.txt"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq 2 "$(count_commits "$repo")" "a subject-only reply still commits"
  assert_eq "fix: handle empty input" "$(git -C "$repo" log -1 --format=%s)" "subject preserved"
  assert_contains "$(git -C "$repo" log -1 --format=%b)" "Checkpoint of work in progress" \
    "the fallback description says what was committed"
}

test_falls_back_without_a_model() {
  local repo state broken
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo fallback)"
  state="$(state_dir fallback)"
  broken="$TEST_ROOT/broken"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$broken"
  chmod +x "$broken"
  printf 'hello\n' > "$repo/new.txt"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$broken" >/dev/null
  # A checkpoint with a dull message beats a lost checkpoint.
  assert_eq 2 "$(count_commits "$repo")" "an unreachable model still commits"
  assert_contains "$(git -C "$repo" log -1 --format=%s)" "chore: files changed" \
    "the fallback subject is used"
}

test_falls_back_when_the_model_is_slow() {
  local repo state slow started elapsed
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo slow)"
  state="$(state_dir slow)"
  slow="$TEST_ROOT/slow-model"
  printf '#!/usr/bin/env bash\nsleep 30\nprintf "feat: never arrives\\n"\n' > "$slow"
  chmod +x "$slow"
  printf 'hello\n' > "$repo/new.txt"
  printf 'more\n' > "$repo/other.txt"

  started="$(date +%s)"
  AUTO_COMMIT_EVERY=1 AUTO_COMMIT_TIMEOUT=2 fire "$repo" "$state" "$slow" >/dev/null
  elapsed=$(( $(date +%s) - started ))

  # The commit is what matters; a subject that arrives late is worthless because
  # the next tool call has already raced it.
  [ "$elapsed" -lt 15 ] || fail_test "the slow model was not bounded: took ${elapsed}s"
  assert_eq 2 "$(count_commits "$repo")" "a slow model still produces a commit"
  assert_contains "$(git -C "$repo" log -1 --format=%s)" "files changed" \
    "the static fallback names the files"
}

test_fallback_names_the_changed_files() {
  local repo state broken subject
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo naming)"
  state="$(state_dir naming)"
  broken="$TEST_ROOT/broken-naming"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$broken"
  chmod +x "$broken"
  printf 'a\n' > "$repo/alpha.txt"
  printf 'b\n' > "$repo/beta.txt"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$broken" >/dev/null
  subject="$(git -C "$repo" log -1 --format=%s)"
  assert_contains "$subject" "chore: files changed" "the fallback keeps a conventional type"
  assert_contains "$subject" "alpha.txt" "the fallback names the first file"
  assert_contains "$subject" "beta.txt" "the fallback names the second file"
}

test_fallback_truncates_a_long_file_list() {
  local repo state broken subject i
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo truncating)"
  state="$(state_dir truncating)"
  broken="$TEST_ROOT/broken-trunc"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$broken"
  chmod +x "$broken"
  for i in $(seq 1 9); do printf 'x\n' > "$repo/f$i.txt"; done
  AUTO_COMMIT_EVERY=1 AUTO_COMMIT_FALLBACK_MAX_FILES=3 fire "$repo" "$state" "$broken" >/dev/null
  subject="$(git -C "$repo" log -1 --format=%s)"
  assert_contains "$subject" "+6 more" "the remaining files are counted, not listed"
}

test_commits_untracked_and_modified_together() {
  local repo state stub tracked
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo mixed)"
  state="$(state_dir mixed)"
  stub="$(make_stub mixed "touch two files")"
  printf 'changed\n' >> "$repo/base.txt"
  printf 'brand new\n' > "$repo/added.txt"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
  tracked="$(git -C "$repo" show --pretty=format: --name-only HEAD | grep -c .)"
  assert_eq 2 "$tracked" "both the modified and the untracked file are committed"
  assert_eq "" "$(git -C "$repo" status --porcelain)" "the tree is clean afterwards"
}

test_never_commits_a_credential() {
  local repo state stub output
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo secrets)"
  state="$(state_dir secrets)"
  stub="$(make_stub secrets "add config")"
  printf 'API_KEY=sk-live-not-a-real-key\n' > "$repo/.env"
  printf 'PRIVATE KEY\n' > "$repo/deploy.pem"
  printf 'safe\n' > "$repo/safe.txt"
  output="$(AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub")"

  local committed
  committed="$(git -C "$repo" show --pretty=format: --name-only HEAD)"
  assert_contains "$committed" "safe.txt" "the ordinary file is committed"
  assert_not_contains "$committed" ".env" "an env file is never committed"
  assert_not_contains "$committed" "deploy.pem" "a private key is never committed"
  # They must remain in the working tree, not be silently discarded.
  assert_contains "$(git -C "$repo" status --porcelain)" ".env" "the skipped file survives"
}

test_never_commits_a_key_pasted_into_source() {
  local repo state stub committed status err
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo content-secret)"
  state="$(state_dir content-secret)"
  stub="$(make_stub contentsecret "chore: add config")"
  # An ordinary filename the glob guard would happily pass, with a key inside.
  printf 'AWS_KEY = "AKIA1234567890ABCDEF"\n' > "$repo/settings.py"
  printf 'def add(a, b):\n    return a + b\n' > "$repo/safe.py"

  # `fire` already folds stderr into stdout, so capture it directly.
  set +e
  err="$(AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub")"
  status=$?
  set -e

  committed="$(git -C "$repo" show --pretty=format: --name-only HEAD)"
  assert_contains "$committed" "safe.py" "the safe file is still committed"
  assert_not_contains "$committed" "settings.py" "the file holding a key is not committed"
  assert_contains "$(git -C "$repo" status --porcelain)" "settings.py" "it stays in the working tree"
  assert_eq 2 "$status" "the hook reports the withheld file rather than failing silently"
  assert_contains "$err" "settings.py" "the report names the file"
  assert_contains "$err" "aws-access-key" "the report names the pattern"
  assert_not_contains "$err" "AKIA1234567890ABCDEF" "the secret value is never echoed"
}

test_content_scan_covers_common_key_shapes() {
  local repo state stub n=0 secret
  command -v jq >/dev/null 2>&1 || return 0
  for secret in \
    'sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' \
    'ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' \
    'xoxb-1234567890-ABCDEFGHIJ' \
    'AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' \
    '-----BEGIN RSA PRIVATE KEY-----'; do
    n=$((n + 1))
    repo="$(make_repo "shape-$n")"
    state="$(state_dir "shape-$n")"
    stub="$(make_stub "shape$n" "chore: add config")"
    printf 'token = "%s"\n' "$secret" > "$repo/app.py"
    set +e
    AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null 2>&1
    set -e
    assert_eq 1 "$(count_commits "$repo")" "a $n-th key shape must not be committed"
  done
}

test_ordinary_code_is_not_flagged() {
  local repo state stub
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo nofalsepositive)"
  state="$(state_dir nofalsepositive)"
  stub="$(make_stub nofalsepositive "feat: add helpers")"
  # Things that superficially look secret-ish but must not trip the scan.
  printf 'API_KEY = os.environ["API_KEY"]\npassword = get_password()\nsecret_name = "prod"\n' \
    > "$repo/config.py"
  printf 'const token = await auth.getToken();\n' > "$repo/auth.js"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null 2>&1
  assert_eq 2 "$(count_commits "$repo")" "ordinary code commits normally"
  assert_eq "" "$(git -C "$repo" status --porcelain)" "nothing was withheld"
}

test_commits_on_main() {
  local repo state stub v
  command -v jq >/dev/null 2>&1 || return 0
  # There is no protected-branch guard. The allowlisted repositories are worked
  # on main directly, so refusing there meant the hook silently did nothing in
  # exactly the repositories it was turned on for.
  repo="$(make_repo on-main)"
  state="$(state_dir on-main)"
  stub="$(make_stub onmain "chore: change things")"
  git -C "$repo" switch -q main
  printf 'hello\n' > "$repo/new.txt"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq 2 "$(count_commits "$repo")" "main is committed like any other branch"
  assert_eq "" "$(git -C "$repo" status --porcelain)" "the tree is clean afterwards"

  git -C "$repo" switch -q -c master
  printf 'more\n' >> "$repo/new.txt"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq 3 "$(count_commits "$repo")" "master is committed too"

  # The retired opt-outs must not come back as silent behaviour: setting either
  # to the value that used to block a commit may no longer block one.
  for v in AUTO_COMMIT_ALLOW_PROTECTED AUTO_COMMIT_PROTECTED; do
    git -C "$repo" switch -q main
    printf 'more for %s\n' "$v" >> "$repo/new.txt"
    jq -n '{session_id: "s", tool_name: "Bash"}' \
      | (cd "$repo" && env "$v=0" AUTO_COMMIT_EVERY=1 AUTO_COMMIT_CMD="$stub" \
         XDG_STATE_HOME="$(state_dir "on-main-$v")" "$COMMAND" --hook >/dev/null 2>&1)
    assert_eq "" "$(git -C "$repo" status --porcelain)" "$v=0 does not withhold the commit"
  done
}

test_refuses_a_detached_head() {
  local repo state stub
  command -v jq >/dev/null 2>&1 || return 0
  # A commit on a detached HEAD is unreachable from any branch and is collected
  # the moment HEAD moves, which is the opposite of a checkpoint.
  repo="$(make_repo detached)"
  state="$(state_dir detached)"
  stub="$(make_stub detached "chore: change things")"
  git -C "$repo" checkout -q --detach HEAD
  printf 'hello\n' > "$repo/new.txt"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq 1 "$(count_commits "$repo")" "nothing is committed on a detached HEAD"
  assert_contains "$(git -C "$repo" status --porcelain)" "new.txt" "the file is left dirty"
}

test_bails_on_an_unmerged_index() {
  local repo state stub out
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo unmerged)"
  state="$(state_dir unmerged)"
  stub="$(make_stub unmerged "chore: change things")"

  # A real conflict: two branches editing the same line, merged.
  printf 'one\n' > "$repo/conflict.txt"
  git -C "$repo" add -A >/dev/null 2>&1
  git -C "$repo" commit -q -m "chore: add conflict.txt"
  git -C "$repo" switch -q -c other HEAD~1 2>/dev/null || git -C "$repo" switch -q -c other
  printf 'two\n' > "$repo/conflict.txt"
  git -C "$repo" add -A >/dev/null 2>&1
  git -C "$repo" commit -q -m "chore: other side"
  git -C "$repo" switch -q feature >/dev/null 2>&1
  git -C "$repo" merge other >/dev/null 2>&1 || true

  [ -n "$(git -C "$repo" diff --name-only --diff-filter=U)" ] \
    || fail_test "test setup produced no conflict"
  before="$(count_commits "$repo")"
  out="$(AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub")"
  assert_eq "$before" "$(count_commits "$repo")" "nothing is committed mid-conflict"
  assert_contains "$out" "conflict" "the reason names the conflict"
}

test_bails_on_conflict_markers_in_a_file() {
  local repo state stub out before
  command -v jq >/dev/null 2>&1 || return 0
  # Markers survive `git add`, after which git no longer calls the file unmerged
  # and would otherwise commit it happily.
  repo="$(make_repo markers)"
  state="$(state_dir markers)"
  stub="$(make_stub markers "chore: change things")"
  printf 'start\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> other\nend\n' > "$repo/merged.txt"
  printf 'fine\n' > "$repo/other.txt"
  before="$(count_commits "$repo")"

  out="$(AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub")"
  assert_eq "$before" "$(count_commits "$repo")" "nothing is committed while markers remain"
  assert_contains "$out" "merged.txt" "the reason names the file"
  assert_contains "$out" "resolve the merge first" "the reason says what to do"
}

test_prose_about_conflicts_is_not_mistaken_for_one() {
  local repo state stub
  command -v jq >/dev/null 2>&1 || return 0
  # Documentation may legitimately mention a marker; only both ends together
  # indicate a real conflict.
  repo="$(make_repo conflictdocs)"
  state="$(state_dir conflictdocs)"
  stub="$(make_stub conflictdocs "docs: explain conflicts")"
  printf 'When git conflicts it writes a <<<<<<< marker at the top.\n' > "$repo/GUIDE.md"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null 2>&1
  assert_eq 2 "$(count_commits "$repo")" "prose mentioning one marker still commits"
}

test_skips_during_a_merge() {
  local repo state stub
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo merging)"
  state="$(state_dir merging)"
  stub="$(make_stub merging "change things")"
  printf 'hello\n' > "$repo/new.txt"
  : > "$repo/.git/MERGE_HEAD"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq 1 "$(count_commits "$repo")" "a merge in progress is left alone"
}

test_clean_tree_commits_nothing() {
  local repo state stub output
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo clean)"
  state="$(state_dir clean)"
  stub="$(make_stub clean "change things")"
  output="$(AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub")"
  assert_eq 1 "$(count_commits "$repo")" "a clean tree produces no empty commit"
}

test_dry_run_changes_nothing() {
  local repo stub output
  repo="$(make_repo dryrun)"
  stub="$(make_stub dryrun "add a greeting file")"
  printf 'hello\n' > "$repo/new.txt"
  output="$(cd "$repo" && AUTO_COMMIT_CMD="$stub" "$COMMAND" --dry-run)"
  assert_contains "$output" "add a greeting file" "the message is shown"
  assert_eq 1 "$(count_commits "$repo")" "dry run commits nothing"
  assert_contains "$(git -C "$repo" status --porcelain)" "new.txt" "the file stays uncommitted"
}

test_cannot_be_disabled_by_environment() {
  local repo state stub v
  command -v jq >/dev/null 2>&1 || return 0
  # Committing is mandatory: no environment variable may switch it off, since a
  # kill switch gets reached for exactly when checkpoints matter most.
  for v in AUTO_COMMIT AUTO_COMMIT_DISABLE AUTO_COMMIT_ENABLED NO_AUTO_COMMIT; do
    repo="$(make_repo "mandatory-$v")"
    state="$(state_dir "mandatory-$v")"
    stub="$(make_stub "mandatory$v" "chore: add a file")"
    printf 'hello\n' > "$repo/new.txt"
    jq -n '{session_id: "s", tool_name: "Bash"}' \
      | (cd "$repo" && env "$v=0" AUTO_COMMIT_EVERY=1 AUTO_COMMIT_CMD="$stub" \
         XDG_STATE_HOME="$state" "$COMMAND" --hook >/dev/null 2>&1)
    assert_eq 2 "$(count_commits "$repo")" "$v=0 must not prevent the commit"
  done
}

test_commits_only_in_allowlisted_repositories() {
  local repo state stub out url
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo allowlist)"
  state="$(state_dir allowlist)"
  stub="$(make_stub allowlist "chore: add a file")"

  # A proprietary neighbour of an allowlisted repository must not match: the
  # slugs are compared whole, so medulla-v1 is a different repository entirely.
  for url in \
    git@github.com:tinyhumansai/medulla-v1.git \
    git@github.com:tinyhumansai/medulla-backend.git \
    git@github.com:someone-else/openhuman.git
  do
    git -C "$repo" remote set-url origin "$url"
    printf 'hello\n' > "$repo/new.txt"
    AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
    assert_eq 1 "$(count_commits "$repo")" "$url must not be committed"
    # Silent as a hook, like the other guards, but a manual run says why.
    out="$(cd "$repo" && AUTO_COMMIT_CMD="$stub" "$COMMAND" --dry-run)"
    assert_contains "$out" "allowlist" "$url is refused with a reason"
  done

  # A repository with no remote at all is not on the list either.
  git -C "$repo" remote remove origin
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq 1 "$(count_commits "$repo")" "a remoteless repository is not committed"

  # Each of the three defaults is accepted, in either URL form.
  local slug n=1
  for slug in tinyhumansai/openhuman tinyhumansai/opencompany tinyhumansai/medulla \
              senamakel/openhuman senamakel/opencompany senamakel/medulla; do
    git -C "$repo" remote add origin "git@github.com:$slug.git"
    AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
    assert_eq "$((n + 1))" "$(count_commits "$repo")" "$slug is allowlisted"
    git -C "$repo" remote remove origin
    n=$((n + 1))

    printf 'more\n' >> "$repo/new.txt"
    git -C "$repo" remote add origin "https://github.com/$slug"
    AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
    assert_eq "$((n + 1))" "$(count_commits "$repo")" "$slug matches as an https URL"
    git -C "$repo" remote remove origin
    n=$((n + 1))
    printf 'more\n' >> "$repo/new.txt"
  done
}

test_allowlist_matches_any_remote_and_is_overridable() {
  local repo state stub
  command -v jq >/dev/null 2>&1 || return 0
  repo="$(make_repo allowlist-remotes)"
  state="$(state_dir allowlist-remotes)"
  stub="$(make_stub allowlistremotes "chore: add a file")"

  # origin is routinely a personal fork, so an allowlisted upstream counts.
  git -C "$repo" remote set-url origin git@github.com:someone-else/medulla.git
  git -C "$repo" remote add upstream git@github.com:tinyhumansai/medulla.git
  printf 'hello\n' > "$repo/new.txt"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq 2 "$(count_commits "$repo")" "an allowlisted upstream is enough"

  # The personal fork of an allowlisted repository counts on its own too.
  git -C "$repo" remote remove upstream
  git -C "$repo" remote set-url origin git@github.com:senamakel/medulla.git
  printf 'more\n' >> "$repo/new.txt"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq 3 "$(count_commits "$repo")" "the senamakel fork is allowlisted"

  # Only origin and upstream are consulted, so a stray extra remote naming an
  # allowlisted repository cannot admit an unrelated checkout.
  git -C "$repo" remote set-url origin git@github.com:tinyhumansai/medulla-v1.git
  git -C "$repo" remote add mirror git@github.com:tinyhumansai/medulla.git
  printf 'more\n' >> "$repo/new.txt"
  AUTO_COMMIT_EVERY=1 fire "$repo" "$state" "$stub" >/dev/null
  assert_eq 3 "$(count_commits "$repo")" "a third remote does not admit the repo"

  # And the list itself can be replaced for a one-off repository.
  jq -n '{session_id: "s", tool_name: "Bash"}' \
    | (cd "$repo" && AUTO_COMMIT_EVERY=1 AUTO_COMMIT_CMD="$stub" \
       AUTO_COMMIT_REPOS="tinyhumansai/medulla-v1" XDG_STATE_HOME="$state" \
       "$COMMAND" --hook >/dev/null 2>&1)
  assert_eq 4 "$(count_commits "$repo")" "AUTO_COMMIT_REPOS overrides the default"
}

run_test "commits only in allowlisted repositories" test_commits_only_in_allowlisted_repositories
run_test "the allowlist matches any remote and is overridable" test_allowlist_matches_any_remote_and_is_overridable
run_test "commits on every tool call by default" test_commits_on_every_tool_call_by_default
run_test "commits the tool worktree instead of the launch checkout" test_commits_the_tool_worktree_not_the_launch_checkout
run_test "commits only every Nth tool call when configured" test_commits_only_every_nth_tool_call
run_test "uses the generated subject" test_uses_the_generated_subject
run_test "keeps an already-conventional subject verbatim" test_keeps_a_conventional_subject_verbatim
run_test "commits a description body" test_commits_a_description_body
run_test "a subject-only reply still commits" test_subject_only_reply_still_commits
run_test "falls back to a plain subject without a model" test_falls_back_without_a_model
run_test "falls back when the model is slow" test_falls_back_when_the_model_is_slow
run_test "the fallback names the changed files" test_fallback_names_the_changed_files
run_test "the fallback truncates a long file list" test_fallback_truncates_a_long_file_list
run_test "commits untracked and modified files together" test_commits_untracked_and_modified_together
run_test "never commits a credential" test_never_commits_a_credential
run_test "never commits a key pasted into source" test_never_commits_a_key_pasted_into_source
run_test "the content scan covers common key shapes" test_content_scan_covers_common_key_shapes
run_test "ordinary code is not flagged" test_ordinary_code_is_not_flagged
run_test "commits on main and master" test_commits_on_main
run_test "refuses a detached HEAD" test_refuses_a_detached_head
run_test "bails on an unmerged index" test_bails_on_an_unmerged_index
run_test "bails on conflict markers in a file" test_bails_on_conflict_markers_in_a_file
run_test "prose about conflicts is not mistaken for one" test_prose_about_conflicts_is_not_mistaken_for_one
run_test "skips during a merge" test_skips_during_a_merge
run_test "a clean tree commits nothing" test_clean_tree_commits_nothing
run_test "dry run changes nothing" test_dry_run_changes_nothing
run_test "cannot be disabled by any environment variable" test_cannot_be_disabled_by_environment
printf '1..%s\n' "$PASS_COUNT"
