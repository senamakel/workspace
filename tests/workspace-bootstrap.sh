#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INIT="$ROOT/bin/workspace-init"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/workspace-bootstrap-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
PASS_COUNT=0

fail_test() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [ "$expected" = "$actual" ] \
    || fail_test "$message: expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail_test "$message: missing '$needle'" ;;
  esac
}

assert_exists() {
  [ -e "$1" ] || fail_test "$2: missing $1"
}

assert_missing() {
  [ ! -e "$1" ] && [ ! -L "$1" ] || fail_test "$2: found $1"
}

assert_line_count() {
  local expected="$1" pattern="$2" file="$3" message="$4" actual
  actual="$(grep -cF -- "$pattern" "$file" || true)"
  assert_eq "$expected" "$actual" "$message"
}

run_test() {
  local name="$1"
  shift
  "$@"
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s - %s\n' "$PASS_COUNT" "$name"
}

new_home() {
  local name="$1" home
  home="$TEST_ROOT/$name/home"
  mkdir -p "$home"
  printf '%s\n' "$home"
}

make_fake_git() {
  local fake_bin="$1" log="$2"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_GIT_LOG"
if [ "${1:-}" = "clone" ]; then
  destination="${4:?missing clone destination}"
  mkdir -p "$destination/.git"
fi
EOF
  chmod +x "$fake_bin/git"
  cat > "$fake_bin/workflow-remotes" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'workflow-remotes %s\n' "$*" >> "$FAKE_GIT_LOG"
EOF
  chmod +x "$fake_bin/workflow-remotes"
  : > "$log"
}

expected_repository_names() {
  cat <<'EOF'
workflow-openhuman
workflow-medulla
workflow-tinyplace
workflow-opencompany
workflow-dashboard
tiny.place
tinyagents
tinyanalyzer
tinybox
tinybrowser
tinybus
tinychannels
tinyconnectors
tinycortex
tinydesktop
tinydocs
tinyflows
tinyhosts
tinyhivemind
tinyinference
tinyjuice
tinyloops
tinymcp
tinymemory
tinyruntime
tinyruntime-nodejs
tinyruntime-python
tinyskills
tinysweeper
tinyteams
tinytools
tinyvoice
tinywallet
tinyworkspaces
EOF
}

run_init() {
  local home="$1" fake_bin="$2"
  shift 2
  HOME="$home" PATH="$fake_bin:/usr/bin:/bin" FAKE_GIT_LOG="$home/git.log" \
    WORKFLOW_REMOTES_COMMAND="$fake_bin/workflow-remotes" "$INIT" "$@"
}

assert_invalid() {
  local home="$1" fake_bin="$2"
  shift 2
  local output status
  set +e
  output="$(run_init "$home" "$fake_bin" "$@" 2>&1)"
  status=$?
  set -e
  assert_eq 1 "$status" "invalid arguments fail: $*"
  assert_contains "$output" \
    "workspace-init [--dry-run] [--workspace <path>]" \
    "usage is shown: $*"
}

test_clones_exact_repository_set() {
  local home fake_bin log output actual_names repository_name
  home="$(new_home clone-set)"
  fake_bin="$home/fake-bin"
  log="$home/git.log"
  make_fake_git "$fake_bin" "$log"

  output="$(run_init "$home" "$fake_bin" --workspace "$home/custom")"

  actual_names="$(awk '/^clone / { sub(/^.*\//, "", $NF); print $NF }' "$log")"
  assert_eq "$(expected_repository_names)" "$actual_names" \
    "the complete workflow and tiny-library set is cloned in manifest order"
  assert_line_count 34 "clone --recurse-submodules" "$log" \
    "exactly 33 recursive SSH clones are issued"
  assert_line_count 5 "workflow-remotes " "$log" \
    "every cloned workflow is configured"
  for repository_name in openhuman medulla tinyplace opencompany dashboard; do
    assert_exists "$home/custom/workflow-$repository_name" \
      "$repository_name destination is created"
  done
  assert_contains "$output" "[clone] workflow-openhuman" \
    "clone progress is reported"
  assert_contains "$(cat "$log")" \
    "clone --recurse-submodules git@github.com:senamakel/tinyagents.git $home/custom/tinyagents" \
    "forked libraries clone from the fork"
  assert_contains "$(cat "$log")" \
    "remote set-url upstream git@github.com:tinyhumansai/tinyagents.git" \
    "forked libraries point upstream at TinyHumans"
  assert_contains "$(cat "$log")" \
    "clone --recurse-submodules git@github.com:tinyhumansai/tinytools.git $home/custom/tinytools" \
    "libraries without a fork clone from TinyHumans"
  assert_exists "$home/bin" "HOME/bin is created"
}

test_existing_destinations_are_preserved_and_git_checkouts_are_configured() {
  local home fake_bin log workspace directory_marker file_marker symlink_target
  local no_git_home no_git_bin repository_name
  home="$(new_home existing)"
  fake_bin="$home/fake-bin"
  log="$home/git.log"
  make_fake_git "$fake_bin" "$log"
  workspace="$home/work"
  mkdir -p "$workspace/workflow-openhuman"
  mkdir -p "$workspace/workflow-openhuman/.git"
  directory_marker="$workspace/workflow-openhuman/do-not-touch"
  printf 'preserve directory\n' > "$directory_marker"
  file_marker="$workspace/workflow-medulla"
  printf 'preserve file\n' > "$file_marker"
  symlink_target="$home/nonexistent-symlink-target"
  ln -s "$symlink_target" "$workspace/workflow-tinyplace"
  mkdir -p "$workspace/tinyagents/.git"

  run_init "$home" "$fake_bin" >/dev/null

  assert_eq "preserve directory" "$(cat "$directory_marker")" \
    "existing directory contents are untouched"
  assert_eq "preserve file" "$(cat "$file_marker")" \
    "existing file contents are untouched"
  assert_eq "$symlink_target" "$(readlink "$workspace/workflow-tinyplace")" \
    "existing symlink is untouched"
  assert_contains "$(cat "$log")" \
    "workflow-remotes $workspace/workflow-openhuman" \
    "existing Git checkout is configured"
  assert_contains "$(cat "$log")" \
    "-C $workspace/tinyagents remote set-url origin git@github.com:senamakel/tinyagents.git" \
    "existing forked library keeps the fork as origin"
  assert_contains "$(cat "$log")" \
    "-C $workspace/tinyagents remote set-url upstream git@github.com:tinyhumansai/tinyagents.git" \
    "existing forked library points upstream at TinyHumans"
  assert_line_count 0 "workflow-medulla.git" "$log" \
    "existing file makes no Git call"
  assert_line_count 0 "workflow-tinyplace.git" "$log" \
    "existing symlink makes no Git call"
  assert_line_count 30 "clone --recurse-submodules" "$log" \
    "only missing repositories are cloned"
  assert_contains "$(cat "$log")" "workflow-opencompany.git" \
    "missing opencompany repository is cloned"
  assert_contains "$(cat "$log")" "workflow-dashboard.git" \
    "missing dashboard repository is cloned"

  no_git_home="$(new_home no-git-needed)"
  no_git_bin="$no_git_home/path"
  mkdir -p "$no_git_home/work" "$no_git_home/bin" "$no_git_bin"
  cat > "$no_git_bin/git" <<'EOF'
#!/usr/bin/env bash
exit 99
EOF
  chmod +x "$no_git_bin/git"
  for repository_name in \
    workflow-openhuman \
    workflow-medulla \
    workflow-tinyplace \
    workflow-opencompany \
    workflow-dashboard \
    tiny.place \
    tinyagents \
    tinyanalyzer \
    tinybox \
    tinybrowser \
    tinybus \
    tinychannels \
    tinyconnectors \
    tinycortex \
    tinydesktop \
    tinydocs \
    tinyflows \
    tinyhosts \
    tinyhivemind \
    tinyinference \
    tinyjuice \
    tinyloops \
    tinymcp \
    tinymemory \
    tinyruntime \
    tinyruntime-nodejs \
    tinyruntime-python \
    tinyskills \
    tinysweeper \
    tinyteams \
    tinytools \
    tinyvoice \
    tinywallet \
    tinyworkspaces
  do
    mkdir "$no_git_home/work/$repository_name"
  done
  HOME="$no_git_home" PATH="$no_git_bin:/usr/bin:/bin" "$INIT" >/dev/null \
    || fail_test "Git is not required when every destination exists"
}

test_dry_run_and_argument_handling() {
  local home fake_bin log output
  home="$(new_home dry-run)"
  fake_bin="$home/fake-bin"
  log="$home/git.log"
  make_fake_git "$fake_bin" "$log"

  output="$(run_init "$home" "$fake_bin" --dry-run --workspace "$home/preview")"

  assert_contains "$output" "[would create] $home/preview" \
    "workspace creation is previewed"
  assert_contains "$output" "[would create] $home/bin" \
    "HOME/bin creation is previewed"
  assert_contains "$output" \
    "[would clone] git@github.com:tinyhumansai/workflow-dashboard.git -> $home/preview/workflow-dashboard" \
    "clone actions are previewed"
  assert_contains "$output" \
    "[would configure] recursive remotes in $home/preview/workflow-dashboard" \
    "remote configuration is previewed"
  assert_contains "$output" \
    "[would clone] git@github.com:senamakel/tinyagents.git -> $home/preview/tinyagents" \
    "fork clone actions are previewed"
  assert_contains "$output" \
    "[would configure] origin senamakel/tinyagents, upstream tinyhumansai/tinyagents" \
    "fork remote configuration is previewed"
  assert_line_count 0 "" "$log" "dry run never calls Git"
  assert_missing "$home/preview" "dry run does not create workspace"
  assert_missing "$home/bin" "dry run does not create HOME/bin"

  output="$(run_init "$home" "$fake_bin" --help)"
  assert_contains "$output" \
    "workspace-init [--dry-run] [--workspace <path>]" \
    "long help is supported"
  output="$(run_init "$home" "$fake_bin" -h)"
  assert_contains "$output" \
    "workspace-init [--dry-run] [--workspace <path>]" \
    "short help is supported"

  assert_invalid "$home" "$fake_bin" --unknown
  assert_invalid "$home" "$fake_bin" --workspace
  assert_invalid "$home" "$fake_bin" --workspace --dry-run
  assert_invalid "$home" "$fake_bin" --workspace ""
  assert_invalid "$home" "$fake_bin" --dry-run --dry-run
  assert_invalid "$home" "$fake_bin" \
    --workspace "$home/a" --workspace "$home/b"
  assert_invalid "$home" "$fake_bin" unexpected
  assert_invalid "$home" "$fake_bin" --dry-run unexpected
  assert_invalid "$home" "$fake_bin" --help unexpected
  assert_invalid "$home" "$fake_bin" --help --help
}

run_test "clones the exact repository set" test_clones_exact_repository_set
run_test "preserves existing paths and configures Git checkouts" \
  test_existing_destinations_are_preserved_and_git_checkouts_are_configured
run_test "keeps dry-run inert and validates arguments" \
  test_dry_run_and_argument_handling
printf '1..%s\n' "$PASS_COUNT"
