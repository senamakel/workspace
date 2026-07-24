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
  mkdir -p "$destination"
fi
EOF
  chmod +x "$fake_bin/git"
  : > "$log"
}

run_init() {
  local home="$1" fake_bin="$2"
  shift 2
  HOME="$home" PATH="$fake_bin:/usr/bin:/bin" FAKE_GIT_LOG="$home/git.log" \
    "$INIT" "$@"
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
  local home fake_bin log output expected repository_name
  home="$(new_home clone-set)"
  fake_bin="$home/fake-bin"
  log="$home/git.log"
  make_fake_git "$fake_bin" "$log"

  output="$(run_init "$home" "$fake_bin" --workspace "$home/custom")"

  expected="clone --recurse-submodules git@github.com:tinyhumansai/workflow-openhuman.git $home/custom/workflow-openhuman
clone --recurse-submodules git@github.com:tinyhumansai/workflow-medulla.git $home/custom/workflow-medulla
clone --recurse-submodules git@github.com:tinyhumansai/workflow-tinyplace.git $home/custom/workflow-tinyplace
clone --recurse-submodules git@github.com:tinyhumansai/workflow-opencompany.git $home/custom/workflow-opencompany
clone --recurse-submodules git@github.com:tinyhumansai/workflow-dashboard.git $home/custom/workflow-dashboard"
  assert_eq "$expected" "$(cat "$log")" \
    "exactly five recursive SSH clones are issued in manifest order"
  for repository_name in openhuman medulla tinyplace opencompany dashboard; do
    assert_exists "$home/custom/workflow-$repository_name" \
      "$repository_name destination is created"
  done
  assert_contains "$output" "[clone] workflow-openhuman" \
    "clone progress is reported"
  assert_exists "$home/bin" "HOME/bin is created"
}

test_existing_destinations_are_opaque() {
  local home fake_bin log workspace directory_marker file_marker symlink_target
  local no_git_home no_git_bin repository_name
  home="$(new_home existing)"
  fake_bin="$home/fake-bin"
  log="$home/git.log"
  make_fake_git "$fake_bin" "$log"
  workspace="$home/work"
  mkdir -p "$workspace/workflow-openhuman"
  directory_marker="$workspace/workflow-openhuman/do-not-touch"
  printf 'preserve directory\n' > "$directory_marker"
  file_marker="$workspace/workflow-medulla"
  printf 'preserve file\n' > "$file_marker"
  symlink_target="$home/nonexistent-symlink-target"
  ln -s "$symlink_target" "$workspace/workflow-tinyplace"

  run_init "$home" "$fake_bin" >/dev/null

  assert_eq "preserve directory" "$(cat "$directory_marker")" \
    "existing directory contents are untouched"
  assert_eq "preserve file" "$(cat "$file_marker")" \
    "existing file contents are untouched"
  assert_eq "$symlink_target" "$(readlink "$workspace/workflow-tinyplace")" \
    "existing symlink is untouched"
  assert_line_count 0 "workflow-openhuman.git" "$log" \
    "existing directory makes no Git call"
  assert_line_count 0 "workflow-medulla.git" "$log" \
    "existing file makes no Git call"
  assert_line_count 0 "workflow-tinyplace.git" "$log" \
    "existing symlink makes no Git call"
  assert_line_count 2 "clone --recurse-submodules" "$log" \
    "only missing repositories are cloned"
  assert_contains "$(cat "$log")" "workflow-opencompany.git" \
    "missing opencompany repository is cloned"
  assert_contains "$(cat "$log")" "workflow-dashboard.git" \
    "missing dashboard repository is cloned"

  no_git_home="$(new_home no-git-needed)"
  no_git_bin="$no_git_home/path"
  mkdir -p "$no_git_home/work" "$no_git_home/bin" "$no_git_bin"
  ln -s /bin/bash "$no_git_bin/bash"
  for repository_name in \
    workflow-openhuman \
    workflow-medulla \
    workflow-tinyplace \
    workflow-opencompany \
    workflow-dashboard
  do
    mkdir "$no_git_home/work/$repository_name"
  done
  HOME="$no_git_home" PATH="$no_git_bin" "$INIT" >/dev/null \
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
run_test "leaves existing destinations opaque" test_existing_destinations_are_opaque
run_test "keeps dry-run inert and validates arguments" \
  test_dry_run_and_argument_handling
printf '1..%s\n' "$PASS_COUNT"
