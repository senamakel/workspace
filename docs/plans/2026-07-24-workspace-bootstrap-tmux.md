# Workspace Bootstrap and Tmux Implementation Plan

> **For agentic workers:** execute this plan task-by-task using the
> subagent-driven-development skill (dispatch a fresh tdd-implementer agent per
> task, then a code-reviewer agent) or the plan-executor agent. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a conservative five-repository workspace bootstrap, a persistent Mac mini tmux launcher, and a repository-managed local `super-review` launcher.
**Architecture:** A dependency-free shell integration suite drives all behavior through temporary homes and fake `git`, `tmux`, `btop`, and `mosh` executables. The two launchers keep their repository lists, window order, styling, remote commands, and attach policy explicit while sourcing a small Bash helper that owns only tmux pane construction.
**Tech Stack:** Bash 3-compatible shell scripts, tmux CLI, Git CLI, POSIX filesystem operations, fake-executable shell integration tests.

## Global Constraints

- Treat `docs/specs/2026-07-24-workspace-bootstrap-tmux-design.md` as the approved contract; do not alter it during implementation.
- Use `$HOME/work` as `workspace-init`'s default and `$HOME/work/tinyhumansai` as `super-review`'s repository root.
- Clone exactly the five `tinyhumansai/workflow-*` SSH remotes from the design with `git clone --recurse-submodules`.
- Never inspect, fetch, pull, reset, update submodules in, or otherwise modify an existing bootstrap destination, whether it is a file, directory, or symlink.
- A bootstrap dry run must perform no writes and make no Git calls.
- Keep repository lists, window order, theme, remote commands, and attach behavior in the launchers rather than the shared helper.
- Resolve `git`, `tmux`, `btop`, and `mosh` through `PATH`, with a clear error only when the command is required.
- Never execute either launcher against a live tmux server during tests or validation.
- Keep all scripts compatible with the repository's Bash style: `#!/usr/bin/env bash`, `set -euo pipefail`, two-space indentation, and quoted expansions.
- Run `./install.sh` only from the primary checkout; from this worktree use `./install.sh --dry-run` exclusively.
- Every task ends with the exact `atomic-commit` command shown; do not batch tasks.

## File Structure

- **Create:** `tests/workspace-bootstrap.sh` — executable integration suite, assertions, temporary homes, and fake command logging/state.
- **Create:** `bin/workspace-init` — local argument parsing, conservative clone pass, backup, and `mosh-tmux` link installation.
- **Create:** `bin/tmux-layouts.sh` — non-executable sourced helper containing only session/window and pane-layout primitives.
- **Create:** `bin/workspace-tmux` — dedicated-server remote workspace launcher and remote theme.
- **Create:** `bin/super-review` — canonical destructive local dashboard launcher.
- **Modify:** `install.sh` — manage `$HOME/super-review.sh` through the existing `link()` function.
- **Modify:** `README.md` — document bootstrap, repository set, launchers, links, and destructive behavior.

---

## Task 1: Validate bootstrap arguments and clone only missing repositories

**Files**

- Create: `tests/workspace-bootstrap.sh`
- Create: `bin/workspace-init`

**Interfaces**

- Consumes: `workspace-init [--dry-run] [--workspace <path>]`, `$HOME`, `PATH`, and the checkout containing `bin/workspace-init`.
- Produces: `usage()`, `fail <message>`, `require_command <name>`, `ensure_directory <path>`, and a clone pass over five exact `name|remote` records.

- [ ] Create `tests/workspace-bootstrap.sh`, mark it executable, and include this complete initial harness:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INIT="$ROOT/bin/workspace-init"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/workspace-bootstrap-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
PASS_COUNT=0

fail_test() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [ "$expected" = "$actual" ] || fail_test "$message: expected '$expected', got '$actual'"
}
assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  case "$haystack" in *"$needle"*) ;; *) fail_test "$message: missing '$needle'" ;; esac
}
assert_exists() { [ -e "$1" ] || fail_test "$2: missing $1"; }
assert_missing() { [ ! -e "$1" ] && [ ! -L "$1" ] || fail_test "$2: found $1"; }
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
  local name="$1" home="$TEST_ROOT/$name/home"
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
  HOME="$home" PATH="$fake_bin:/usr/bin:/bin" FAKE_GIT_LOG="$home/git.log" "$INIT" "$@"
}
test_clones_exact_repository_set() {
  local home fake_bin log output
  home="$(new_home clone-set)"
  fake_bin="$home/fake-bin"
  log="$home/git.log"
  make_fake_git "$fake_bin" "$log"
  output="$(run_init "$home" "$fake_bin" --workspace "$home/custom")"
  assert_line_count 5 "clone --recurse-submodules" "$log" "five clones are issued"
  for name in openhuman medulla tinyplace opencompany dashboard; do
    assert_contains "$(cat "$log")" \
      "git@github.com:tinyhumansai/workflow-$name.git $home/custom/workflow-$name" \
      "$name uses its exact SSH remote and destination"
    assert_exists "$home/custom/workflow-$name" "$name destination is created"
  done
  assert_contains "$output" "[clone] workflow-openhuman" "clone progress is reported"
}
test_existing_destinations_are_opaque() {
  local home fake_bin log destination marker
  home="$(new_home existing)"
  fake_bin="$home/fake-bin"
  log="$home/git.log"
  make_fake_git "$fake_bin" "$log"
  destination="$home/work/workflow-openhuman"
  mkdir -p "$destination"
  marker="$destination/do-not-touch"
  printf 'preserve\n' > "$marker"
  run_init "$home" "$fake_bin" >/dev/null
  assert_eq "preserve" "$(cat "$marker")" "existing contents are untouched"
  assert_line_count 0 "workflow-openhuman.git" "$log" "existing destination makes no Git call"
  assert_line_count 4 "clone --recurse-submodules" "$log" "remaining repositories are cloned"
}
test_dry_run_and_invalid_arguments() {
  local home fake_bin log output status
  home="$(new_home dry-run)"
  fake_bin="$home/fake-bin"
  log="$home/git.log"
  make_fake_git "$fake_bin" "$log"
  output="$(run_init "$home" "$fake_bin" --dry-run --workspace "$home/preview")"
  assert_contains "$output" "[would create] $home/preview" "workspace creation is previewed"
  assert_line_count 0 "" "$log" "dry run never calls Git"
  assert_missing "$home/preview" "dry run does not create workspace"
  assert_missing "$home/bin" "dry run does not create bin"
  for args in "--unknown" "--workspace" "--workspace --dry-run" "--dry-run --dry-run" "--workspace $home/a --workspace $home/b"; do
    set +e
    output="$(run_init "$home" "$fake_bin" $args 2>&1)"
    status=$?
    set -e
    assert_eq 1 "$status" "invalid arguments fail: $args"
    assert_contains "$output" "workspace-init [--dry-run] [--workspace <path>]" "usage is shown: $args"
  done
}
run_test "clones the exact repository set" test_clones_exact_repository_set
run_test "leaves existing destinations opaque" test_existing_destinations_are_opaque
run_test "keeps dry-run inert and rejects invalid arguments" test_dry_run_and_invalid_arguments
printf '1..%s\n' "$PASS_COUNT"
```

- [ ] Run `tests/workspace-bootstrap.sh`; expect failure because `bin/workspace-init` does not exist.

- [ ] Create `bin/workspace-init`, mark it executable, and use this minimal implementation (link installation deliberately arrives in Task 2):

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
workspace-init [--dry-run] [--workspace <path>]

Create missing TinyHumans workflow checkouts without changing existing paths.
  --dry-run          describe actions without writing or contacting GitHub
  --workspace <path> use a workspace other than $HOME/work
  -h, --help         show this help
EOF
}
fail() { printf 'workspace-init: %s\n' "$1" >&2; usage >&2; }
require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'workspace-init: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

DRY_RUN=0
DRY_RUN_SEEN=0
WORKSPACE="$HOME/work"
WORKSPACE_SEEN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      [ "$DRY_RUN_SEEN" -eq 0 ] || { fail "repeated argument: --dry-run"; exit 1; }
      DRY_RUN=1
      DRY_RUN_SEEN=1
      ;;
    --workspace)
      [ "$WORKSPACE_SEEN" -eq 0 ] || { fail "repeated argument: --workspace"; exit 1; }
      [ "$#" -ge 2 ] || { fail "missing value for --workspace"; exit 1; }
      case "$2" in --*) fail "missing value for --workspace"; exit 1 ;; esac
      WORKSPACE="$2"
      WORKSPACE_SEEN=1
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1"; exit 1 ;;
  esac
  shift
done

ensure_directory() {
  local directory="$1"
  [ -d "$directory" ] && return
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[would create] %s\n' "$directory"
  else
    mkdir -p "$directory"
    printf '[create] %s\n' "$directory"
  fi
}

ensure_directory "$WORKSPACE"
ensure_directory "$HOME/bin"
REPOSITORIES='workflow-openhuman|git@github.com:tinyhumansai/workflow-openhuman.git
workflow-medulla|git@github.com:tinyhumansai/workflow-medulla.git
workflow-tinyplace|git@github.com:tinyhumansai/workflow-tinyplace.git
workflow-opencompany|git@github.com:tinyhumansai/workflow-opencompany.git
workflow-dashboard|git@github.com:tinyhumansai/workflow-dashboard.git'
while IFS='|' read -r name remote; do
  destination="$WORKSPACE/$name"
  if [ -e "$destination" ] || [ -L "$destination" ]; then
    printf '[skip] existing destination: %s\n' "$destination"
    continue
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[would clone] %s -> %s\n' "$remote" "$destination"
  else
    require_command git
    printf '[clone] %s\n' "$name"
    git clone --recurse-submodules "$remote" "$destination"
  fi
done <<EOF
$REPOSITORIES
EOF
```

- [ ] Run `tests/workspace-bootstrap.sh`, `bash -n bin/workspace-init tests/workspace-bootstrap.sh`, and `git diff --check`; expect three passing TAP cases and zero syntax/whitespace errors.

- [ ] Commit this slice:

```bash
atomic-commit "bin: add conservative workspace bootstrap" -- bin/workspace-init tests/workspace-bootstrap.sh
```

---

## Task 2: Install `mosh-tmux` idempotently with recoverable backups

**Files**

- Modify: `tests/workspace-bootstrap.sh`
- Modify: `bin/workspace-init`

**Interfaces**

- Consumes: `CHECKOUT_ROOT`, `$HOME/bin/mosh-tmux`, and `bin/workspace-tmux`.
- Produces: `install_launcher_link <source> <destination>`, with an already-correct link unchanged and a conflict moved to `$HOME/.config-backups/workspace-init-<timestamp>/mosh-tmux`.

- [ ] Before the current `run_test` calls, add:

```bash
test_launcher_link_is_idempotent_and_backed_up() {
  local home fake_bin log target first_target backup
  home="$(new_home links)"
  fake_bin="$home/fake-bin"
  log="$home/git.log"
  make_fake_git "$fake_bin" "$log"
  mkdir -p "$home/work"
  for name in openhuman medulla tinyplace opencompany dashboard; do
    mkdir "$home/work/workflow-$name"
  done
  run_init "$home" "$fake_bin" >/dev/null
  target="$home/bin/mosh-tmux"
  assert_eq "$ROOT/bin/workspace-tmux" "$(readlink "$target")" "launcher link targets this checkout"
  first_target="$(readlink "$target")"
  run_init "$home" "$fake_bin" >/dev/null
  assert_eq "$first_target" "$(readlink "$target")" "second run preserves the correct link"
  rm "$target"
  printf 'old launcher\n' > "$target"
  run_init "$home" "$fake_bin" >/dev/null
  backup="$(find "$home/.config-backups" -type f -name mosh-tmux -print)"
  assert_eq "old launcher" "$(cat "$backup")" "conflict is recoverable from backup"
  assert_eq "$ROOT/bin/workspace-tmux" "$(readlink "$target")" "link replaces the backed-up conflict"
}
```

Add `run_test "installs and safely replaces the launcher link" test_launcher_link_is_idempotent_and_backed_up` before the TAP plan line.

- [ ] Run `tests/workspace-bootstrap.sh`; expect the new case to fail because `$HOME/bin/mosh-tmux` is missing.

- [ ] Add `CHECKOUT_ROOT` immediately after `set -euo pipefail`, then append the link implementation:

```bash
CHECKOUT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
```

```bash
install_launcher_link() {
  local source="$1" destination="$2" backup_dir
  if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source" ]; then
    printf '[ok] %s\n' "$destination"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -e "$destination" ] || [ -L "$destination" ]; then
      printf '[would replace] %s -> %s (backing up old)\n' "$destination" "$source"
    else
      printf '[would link] %s -> %s\n' "$destination" "$source"
    fi
    return
  fi
  if [ -e "$destination" ] || [ -L "$destination" ]; then
    backup_dir="$HOME/.config-backups/workspace-init-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    mv "$destination" "$backup_dir/$(basename "$destination")"
    printf '[backup] %s -> %s/\n' "$destination" "$backup_dir"
  fi
  ln -s "$source" "$destination"
  printf '[link] %s -> %s\n' "$destination" "$source"
}
install_launcher_link "$CHECKOUT_ROOT/bin/workspace-tmux" "$HOME/bin/mosh-tmux"
```

- [ ] Run `tests/workspace-bootstrap.sh` twice, then `bash -n bin/workspace-init tests/workspace-bootstrap.sh` and `git diff --check`. Both suite runs must report four passes; the second run proves test isolation as well as command idempotency.

- [ ] Commit:

```bash
atomic-commit "bin: install the remote tmux launcher safely" -- bin/workspace-init tests/workspace-bootstrap.sh
```

---

## Task 3: Add reusable tmux layout primitives

**Files**

- Create: `bin/tmux-layouts.sh`
- Modify: `tests/workspace-bootstrap.sh`

**Interfaces**

- Consumes: an executable path, optional tmux server name, session name, window name, and one or four working directories.
- Produces: `tmux_call`, `tmux_create_window`, `tmux_make_quad_window`, `tmux_make_grid_window`, and `tmux_make_mixed_quad_window`; layout builders print no pane id to stdout.

- [ ] Add a fake tmux that returns deterministic pane ids and logs every argument, plus one direct helper test:

```bash
make_fake_tmux() {
  local fake_bin="$1"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_TMUX_LOG"
case " $* " in
  *" has-session "*)
    [ -e "$FAKE_TMUX_STATE" ]
    exit
    ;;
  *" kill-session "*)
    rm -f "$FAKE_TMUX_STATE"
    exit
    ;;
  *" new-session "*)
    : > "$FAKE_TMUX_STATE"
    ;;
esac
case " $* " in
  *" display-message "*) printf '@1\n' ;;
  *" -P -F "*) printf '@1\n' ;;
esac
EOF
  chmod +x "$fake_bin/tmux"
}
test_shared_layout_primitives() {
  local home fake_bin log output
  home="$(new_home layouts)"
  fake_bin="$home/fake-bin"
  log="$home/tmux.log"
  make_fake_tmux "$fake_bin"
  mkdir -p "$home"/{one,two,three,four}
  output="$(
    export FAKE_TMUX_LOG="$log"
    export FAKE_TMUX_STATE="$home/tmux.state"
    # shellcheck source=../bin/tmux-layouts.sh
    source "$ROOT/bin/tmux-layouts.sh"
    tmux_make_grid_window "$fake_bin/tmux" mosh workspace grid "$home/one"
    tmux_make_mixed_quad_window "$fake_bin/tmux" "" local mixed \
      "$home/one" "$home/two" "$home/three" "$home/four"
  )"
  assert_eq "" "$output" "helpers do not leak pane ids"
  assert_line_count 1 "new-session -d -x 240 -y 80 -s workspace -n grid -c $home/one" "$log" \
    "first remote window creates a generous detached session"
  assert_line_count 8 "split-window" "$log" "grid and mixed layouts create eight additional panes"
  assert_line_count 2 "select-layout" "$log" "each layout is normalized"
  assert_contains "$(cat "$log")" "select-pane -t @1 -T four" "mixed panes use directory titles"
}
```

Register it before the TAP plan.

- [ ] Run the suite; expect `source: .../bin/tmux-layouts.sh: No such file or directory`.

- [ ] Create non-executable `bin/tmux-layouts.sh` with:

```bash
tmux_call() {
  local tmux_command="$1" server="$2"
  shift 2
  if [ -n "$server" ]; then
    "$tmux_command" -L "$server" "$@"
  else
    "$tmux_command" "$@"
  fi
}
tmux_create_window() {
  local tmux_command="$1" server="$2" session="$3" name="$4" directory="$5"
  if tmux_call "$tmux_command" "$server" has-session -t "$session" 2>/dev/null; then
    tmux_call "$tmux_command" "$server" new-window -t "$session" -n "$name" \
      -c "$directory" -P -F '#{pane_id}'
  else
    tmux_call "$tmux_command" "$server" new-session -d -x 240 -y 80 \
      -s "$session" -n "$name" -c "$directory"
    tmux_call "$tmux_command" "$server" display-message \
      -t "$session:$name" -p '#{pane_id}'
  fi
}
tmux_make_quad_window() {
  local command="$1" server="$2" session="$3" name="$4" directory="$5"
  local tl tr bl br pane title
  tl="$(tmux_create_window "$command" "$server" "$session" "$name" "$directory")"
  tr="$(tmux_call "$command" "$server" split-window -h -t "$tl" -c "$directory" -P -F '#{pane_id}')"
  bl="$(tmux_call "$command" "$server" split-window -v -t "$tl" -c "$directory" -P -F '#{pane_id}')"
  br="$(tmux_call "$command" "$server" split-window -v -t "$tr" -c "$directory" -P -F '#{pane_id}')"
  title="${directory##*/}"
  for pane in "$tl" "$tr" "$bl" "$br"; do
    tmux_call "$command" "$server" select-pane -t "$pane" -T "$title"
  done
  tmux_call "$command" "$server" select-layout -t "$session:$name" tiled >/dev/null
}
tmux_make_grid_window() {
  local command="$1" server="$2" session="$3" name="$4" directory="$5"
  local tl tr ml mr bl br pane title
  tl="$(tmux_create_window "$command" "$server" "$session" "$name" "$directory")"
  tr="$(tmux_call "$command" "$server" split-window -h -t "$tl" -c "$directory" -P -F '#{pane_id}')"
  ml="$(tmux_call "$command" "$server" split-window -v -t "$tl" -c "$directory" -P -F '#{pane_id}')"
  mr="$(tmux_call "$command" "$server" split-window -v -t "$tr" -c "$directory" -P -F '#{pane_id}')"
  bl="$(tmux_call "$command" "$server" split-window -v -t "$ml" -c "$directory" -P -F '#{pane_id}')"
  br="$(tmux_call "$command" "$server" split-window -v -t "$mr" -c "$directory" -P -F '#{pane_id}')"
  title="${directory##*/}"
  for pane in "$tl" "$tr" "$ml" "$mr" "$bl" "$br"; do
    tmux_call "$command" "$server" select-pane -t "$pane" -T "$title"
  done
  tmux_call "$command" "$server" select-layout -t "$session:$name" tiled >/dev/null
}
tmux_make_mixed_quad_window() {
  local command="$1" server="$2" session="$3" name="$4"
  shift 4
  local directories=("$@") tl tr bl br panes pane index
  [ "${#directories[@]}" -eq 4 ] || return 1
  tl="$(tmux_create_window "$command" "$server" "$session" "$name" "${directories[0]}")"
  tr="$(tmux_call "$command" "$server" split-window -h -t "$tl" -c "${directories[1]}" -P -F '#{pane_id}')"
  bl="$(tmux_call "$command" "$server" split-window -v -t "$tl" -c "${directories[2]}" -P -F '#{pane_id}')"
  br="$(tmux_call "$command" "$server" split-window -v -t "$tr" -c "${directories[3]}" -P -F '#{pane_id}')"
  panes=("$tl" "$tr" "$bl" "$br")
  for index in 0 1 2 3; do
    pane="${panes[$index]}"
    tmux_call "$command" "$server" select-pane -t "$pane" -T "${directories[$index]##*/}"
  done
  tmux_call "$command" "$server" select-layout -t "$session:$name" tiled >/dev/null
}
```

- [ ] Run `tests/workspace-bootstrap.sh`, `bash -n bin/tmux-layouts.sh tests/workspace-bootstrap.sh`, and `git diff --check`; expect five TAP passes.

- [ ] Commit:

```bash
atomic-commit "bin: add shared tmux layout primitives" -- bin/tmux-layouts.sh tests/workspace-bootstrap.sh
```

---

## Task 4: Build and safely reuse the persistent remote workspace

**Files**

- Create: `bin/workspace-tmux`
- Modify: `tests/workspace-bootstrap.sh`

**Interfaces**

- Consumes: `$HOME/work`, `MOSH_TMUX_SERVER` (default `mosh`), `MOSH_TMUX_SESSION` (default `workspace`), `TMUX`, `PATH`, and Task 3 helpers.
- Produces: five fixed 2x3 workflow windows, `btop`, and `shell` on first use; reapplied session options on every run; refusal under nested tmux; final `exec tmux -L <server> attach-session -t <session>`.

- [ ] Add this fake command helper and the complete remote-launcher tests before the `run_test` calls:

```bash
make_fake_command() {
  local fake_bin="$1" name="$2"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/$name" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_bin/$name"
}
run_remote_launcher() {
  local home="$1" fake_bin="$2"
  shift 2
  HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_TMUX_LOG="$home/tmux.log" FAKE_TMUX_STATE="$home/tmux.state" \
    "$@" "$ROOT/bin/workspace-tmux"
}
test_remote_launcher_builds_exact_workspace() {
  local home fake_bin log name
  home="$(new_home remote-new)"
  fake_bin="$home/fake-bin"
  log="$home/tmux.log"
  make_fake_tmux "$fake_bin"
  make_fake_command "$fake_bin" btop
  : > "$log"
  for name in openhuman medulla tinyplace dashboard opencompany; do
    mkdir -p "$home/work/workflow-$name"
  done
  run_remote_launcher "$home" "$fake_bin" env -u TMUX
  assert_line_count 5 "select-layout -t workspace:" "$log" "five workflow grids are built"
  assert_line_count 25 "split-window" "$log" "five grids add five panes each"
  for name in openhuman medulla tinyplace dashboard opencompany; do
    assert_contains "$(cat "$log")" "-n $name -c $home/work/workflow-$name" \
      "$name uses its exact directory"
  done
  assert_contains "$(cat "$log")" "-L mosh new-window -t workspace -n btop -c $home" "btop window is rooted at home"
  assert_contains "$(cat "$log")" "-L mosh new-window -t workspace -n shell -c $home" "shell window is rooted at home"
  assert_contains "$(cat "$log")" "set-option -t workspace prefix C-z" "remote prefix is C-z"
  assert_contains "$(cat "$log")" "set-option -t workspace status-style bg=blue,fg=white" "blue status theme is applied"
  assert_contains "$(cat "$log")" "set-option -t workspace mouse on" "mouse is enabled"
  assert_contains "$(cat "$log")" "set-option -t workspace allow-passthrough on" "passthrough is enabled"
  assert_contains "$(cat "$log")" "set-window-option -t workspace window-style bg=color0" "inactive panes are dimmed"
  assert_contains "$(cat "$log")" "-L mosh attach-session -t workspace" "dedicated server is attached"
}
test_remote_launcher_reuses_and_guards_attach() {
  local home fake_bin log output status
  home="$(new_home remote-existing)"
  fake_bin="$home/fake-bin"
  log="$home/tmux.log"
  make_fake_tmux "$fake_bin"
  : > "$log"
  : > "$home/tmux.state"
  run_remote_launcher "$home" "$fake_bin" env -u TMUX
  assert_line_count 0 "new-session" "$log" "existing session is not recreated"
  assert_line_count 0 "new-window" "$log" "existing session gets no windows"
  assert_line_count 0 "split-window" "$log" "existing session gets no panes"
  assert_contains "$(cat "$log")" "status-style bg=blue,fg=white" "theme is reapplied on reuse"
  : > "$log"
  set +e
  output="$(run_remote_launcher "$home" "$fake_bin" env TMUX=/tmp/outer 2>&1)"
  status=$?
  set -e
  assert_eq 1 "$status" "nested tmux invocation fails"
  assert_contains "$output" "refusing to attach from inside tmux" "nested attach explains refusal"
  assert_line_count 0 "attach-session" "$log" "nested invocation never attaches"
}
```

Register both with:

```bash
run_test "builds the exact persistent remote workspace" test_remote_launcher_builds_exact_workspace
run_test "reuses the remote session and guards attachment" test_remote_launcher_reuses_and_guards_attach
```

The key assertions deliberately include:

```bash
assert_line_count 5 "select-layout -t workspace:" "$log" "five workflow grids are built"
assert_line_count 25 "split-window" "$log" "five grids add five panes each"
assert_contains "$(cat "$log")" "-L mosh new-window -t workspace -n btop -c $home" "btop window is rooted at home"
assert_contains "$(cat "$log")" "-L mosh new-window -t workspace -n shell -c $home" "shell window is rooted at home"
assert_contains "$(cat "$log")" "set-option -t workspace prefix C-z" "remote prefix is C-z"
assert_contains "$(cat "$log")" "set-option -t workspace status-style bg=blue,fg=white" "blue status theme is applied"
assert_contains "$(cat "$log")" "set-option -t workspace mouse on" "mouse is enabled"
assert_contains "$(cat "$log")" "set-option -t workspace allow-passthrough on" "passthrough is enabled"
assert_contains "$(cat "$log")" "set-window-option -t workspace window-style bg=color0" "inactive panes are dimmed"
assert_contains "$(cat "$log")" "-L mosh attach-session -t workspace" "dedicated server is attached"
```

- [ ] Run the suite; expect failure because `bin/workspace-tmux` does not exist.

- [ ] Create executable `bin/workspace-tmux` with this implementation:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=tmux-layouts.sh
source "$ROOT/bin/tmux-layouts.sh"
SERVER="${MOSH_TMUX_SERVER:-mosh}"
SESSION="${MOSH_TMUX_SESSION:-workspace}"
WORKSPACE="$HOME/work"
TMUX_COMMAND="$(command -v tmux || true)"
[ -n "$TMUX_COMMAND" ] || { printf 'workspace-tmux: required command not found: tmux\n' >&2; exit 1; }

if ! tmux_call "$TMUX_COMMAND" "$SERVER" has-session -t "$SESSION" 2>/dev/null; then
  for name in openhuman medulla tinyplace dashboard opencompany; do
    directory="$WORKSPACE/workflow-$name"
    [ -d "$directory" ] || {
      printf 'workspace-tmux: missing workflow directory: %s\n' "$directory" >&2
      exit 1
    }
  done
  BOTTOM="$(command -v btop || true)"
  [ -n "$BOTTOM" ] || { printf 'workspace-tmux: required command not found: btop\n' >&2; exit 1; }
  tmux_make_grid_window "$TMUX_COMMAND" "$SERVER" "$SESSION" openhuman "$WORKSPACE/workflow-openhuman"
  tmux_make_grid_window "$TMUX_COMMAND" "$SERVER" "$SESSION" medulla "$WORKSPACE/workflow-medulla"
  tmux_make_grid_window "$TMUX_COMMAND" "$SERVER" "$SESSION" tinyplace "$WORKSPACE/workflow-tinyplace"
  tmux_make_grid_window "$TMUX_COMMAND" "$SERVER" "$SESSION" dashboard "$WORKSPACE/workflow-dashboard"
  tmux_make_grid_window "$TMUX_COMMAND" "$SERVER" "$SESSION" opencompany "$WORKSPACE/workflow-opencompany"
  pane="$(tmux_create_window "$TMUX_COMMAND" "$SERVER" "$SESSION" btop "$HOME")"
  tmux_call "$TMUX_COMMAND" "$SERVER" select-pane -t "$pane" -T btop
  tmux_call "$TMUX_COMMAND" "$SERVER" send-keys -t "$pane" "$BOTTOM" C-m
  pane="$(tmux_create_window "$TMUX_COMMAND" "$SERVER" "$SESSION" shell "$HOME")"
  tmux_call "$TMUX_COMMAND" "$SERVER" select-pane -t "$pane" -T shell
  tmux_call "$TMUX_COMMAND" "$SERVER" select-window -t "$SESSION:1"
fi

tmux_call "$TMUX_COMMAND" "$SERVER" set-option -t "$SESSION" mouse on
tmux_call "$TMUX_COMMAND" "$SERVER" set-option -t "$SESSION" allow-passthrough on
tmux_call "$TMUX_COMMAND" "$SERVER" set-option -t "$SESSION" prefix C-z
tmux_call "$TMUX_COMMAND" "$SERVER" unbind-key -T prefix C-b
tmux_call "$TMUX_COMMAND" "$SERVER" bind-key -T prefix C-z send-prefix
tmux_call "$TMUX_COMMAND" "$SERVER" set-option -t "$SESSION" status-style bg=blue,fg=white
tmux_call "$TMUX_COMMAND" "$SERVER" set-option -t "$SESSION" message-style bg=blue,fg=white
tmux_call "$TMUX_COMMAND" "$SERVER" set-option -t "$SESSION" pane-active-border-style fg=blue
tmux_call "$TMUX_COMMAND" "$SERVER" set-option -t "$SESSION" pane-border-style fg=color8
tmux_call "$TMUX_COMMAND" "$SERVER" set-window-option -t "$SESSION" window-style bg=color0
tmux_call "$TMUX_COMMAND" "$SERVER" set-window-option -t "$SESSION" window-active-style bg=terminal

[ -z "${TMUX:-}" ] || {
  printf 'workspace-tmux: refusing to attach from inside tmux\n' >&2
  exit 1
}
exec "$TMUX_COMMAND" -L "$SERVER" attach-session -t "$SESSION"
```

- [ ] Run `tests/workspace-bootstrap.sh`, `bash -n bin/workspace-tmux tests/workspace-bootstrap.sh`, and `git diff --check`; expect all cases to pass without contacting live tmux.

- [ ] Commit:

```bash
atomic-commit "bin: add persistent remote tmux workspace" -- bin/workspace-tmux tests/workspace-bootstrap.sh
```

---

## Task 5: Port the canonical destructive local `super-review` launcher

**Files**

- Create: `bin/super-review`
- Modify: `tests/workspace-bootstrap.sh`

**Interfaces**

- Consumes: `super-review [--help]`, `$HOME/work/tinyhumansai`, `PATH`, and Task 3 helpers.
- Produces: deliberate replacement of session `super-review`; five workflow quad windows, one mixed libraries quad, `btop`, `cloud`, `macmini`, and `shell`; pane titles/borders; attach to window 1.

- [ ] Add this complete local-launcher test and register it:

```bash
test_super_review_layout_dependencies_and_help() {
  local home fake_bin log output status name directory
  home="$(new_home super-review)"
  fake_bin="$home/fake-bin"
  log="$home/tmux.log"
  make_fake_tmux "$fake_bin"
  make_fake_command "$fake_bin" btop
  make_fake_command "$fake_bin" mosh
  : > "$log"
  for name in workflow-openhuman workflow-medulla workflow-tinyplace workflow-dashboard workflow-opencompany \
    tinycortex tinyagents tinychannels tinyjuice; do
    mkdir -p "$home/work/tinyhumansai/$name"
  done
  output="$(HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_TMUX_LOG="$log" FAKE_TMUX_STATE="$home/tmux.state" \
    "$ROOT/bin/super-review" --help)"
  assert_contains "$output" "deliberately kills and replaces" "help warns about destructive recreation"
  assert_eq "" "$(cat "$log")" "help does not call tmux"
  HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_TMUX_LOG="$log" FAKE_TMUX_STATE="$home/tmux.state" \
    "$ROOT/bin/super-review"
  assert_contains "$(head -1 "$log")" "kill-session -t super-review" "session replacement is first"
  assert_line_count 6 "select-layout -t super-review:" "$log" "five workflows and libraries get layouts"
  assert_line_count 18 "split-window" "$log" "six four-pane windows add three panes each"
  for name in openhuman medulla tinyplace dashboard opencompany; do
    assert_contains "$(cat "$log")" "-n $name -c $home/work/tinyhumansai/workflow-$name" \
      "$name workflow directory is exact"
  done
  for directory in tinycortex tinyagents tinychannels tinyjuice; do
    assert_contains "$(cat "$log")" "-c $home/work/tinyhumansai/$directory" \
      "$directory is present in libraries"
  done
  assert_contains "$(cat "$log")" \
    "mosh droid@robot1.digital.ocean -- bash -lc 'tmux attach -t super-review || ~/tmux-cloud.sh'" \
    "Robot1 command is preserved"
  assert_contains "$(cat "$log")" "mosh enamakel@mac-mini -- zsh -lc '~/bin/mosh-tmux'" \
    "Mac mini command is preserved"
  assert_contains "$(cat "$log")" "pane-border-status top" "pane titles are enabled"
  assert_contains "$(cat "$log")" "pane-border-format  #{pane_title} " "pane title format is preserved"
  assert_contains "$(cat "$log")" "select-window -t super-review:1" "first window is selected"
  assert_contains "$(cat "$log")" "attach-session -t super-review" "local session is attached"
  rm "$fake_bin/mosh"
  : > "$log"
  set +e
  output="$(HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_TMUX_LOG="$log" FAKE_TMUX_STATE="$home/tmux.state" \
    "$ROOT/bin/super-review" 2>&1)"
  status=$?
  set -e
  assert_eq 1 "$status" "missing mosh fails"
  assert_contains "$output" "required command not found: mosh" "missing mosh is clear"
  assert_eq "" "$(cat "$log")" "dependency failure does not kill the session"
}
run_test "preserves the local super-review dashboard" test_super_review_layout_dependencies_and_help
```

- [ ] Run the suite; expect failure because `bin/super-review` does not exist.

- [ ] Create executable `bin/super-review`:

```bash
#!/usr/bin/env bash
set -euo pipefail
usage() {
  cat <<'EOF'
super-review [--help]

Recreate and attach the local super-review tmux dashboard.
WARNING: this deliberately kills and replaces any existing super-review session.
EOF
}
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) printf 'super-review: unknown argument: %s\n' "$1" >&2; usage >&2; exit 1 ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=tmux-layouts.sh
source "$ROOT/bin/tmux-layouts.sh"
SESSION="super-review"
WORKSPACE="${SUPER_REVIEW_WORKSPACE:-$HOME/work/tinyhumansai}"
TMUX_COMMAND="$(command -v tmux || true)"
BTOP_COMMAND="$(command -v btop || true)"
MOSH_COMMAND="$(command -v mosh || true)"
for pair in "tmux|$TMUX_COMMAND" "btop|$BTOP_COMMAND" "mosh|$MOSH_COMMAND"; do
  name="${pair%%|*}"
  path="${pair#*|}"
  [ -n "$path" ] || { printf 'super-review: required command not found: %s\n' "$name" >&2; exit 1; }
done
tmux_call "$TMUX_COMMAND" "" kill-session -t "$SESSION" 2>/dev/null || true
tmux_make_quad_window "$TMUX_COMMAND" "" "$SESSION" openhuman "$WORKSPACE/workflow-openhuman"
tmux_make_quad_window "$TMUX_COMMAND" "" "$SESSION" medulla "$WORKSPACE/workflow-medulla"
tmux_make_quad_window "$TMUX_COMMAND" "" "$SESSION" tinyplace "$WORKSPACE/workflow-tinyplace"
tmux_make_quad_window "$TMUX_COMMAND" "" "$SESSION" dashboard "$WORKSPACE/workflow-dashboard"
tmux_make_quad_window "$TMUX_COMMAND" "" "$SESSION" opencompany "$WORKSPACE/workflow-opencompany"
tmux_make_mixed_quad_window "$TMUX_COMMAND" "" "$SESSION" libraries \
  "$WORKSPACE/tinycortex" "$WORKSPACE/tinyagents" "$WORKSPACE/tinychannels" "$WORKSPACE/tinyjuice"
pane="$(tmux_create_window "$TMUX_COMMAND" "" "$SESSION" btop "$HOME")"
tmux_call "$TMUX_COMMAND" "" select-pane -t "$pane" -T btop
tmux_call "$TMUX_COMMAND" "" send-keys -t "$pane" "$BTOP_COMMAND" C-m
pane="$(tmux_create_window "$TMUX_COMMAND" "" "$SESSION" cloud "$HOME")"
tmux_call "$TMUX_COMMAND" "" select-pane -t "$pane" -T 'cloud · robot1'
tmux_call "$TMUX_COMMAND" "" send-keys -t "$pane" \
  "mosh droid@robot1.digital.ocean -- bash -lc 'tmux attach -t super-review || ~/tmux-cloud.sh'" C-m
pane="$(tmux_create_window "$TMUX_COMMAND" "" "$SESSION" macmini "$HOME")"
tmux_call "$TMUX_COMMAND" "" select-pane -t "$pane" -T macmini
tmux_call "$TMUX_COMMAND" "" send-keys -t "$pane" \
  "mosh enamakel@mac-mini -- zsh -lc '~/bin/mosh-tmux'" C-m
pane="$(tmux_create_window "$TMUX_COMMAND" "" "$SESSION" shell "$HOME")"
tmux_call "$TMUX_COMMAND" "" select-pane -t "$pane" -T shell
tmux_call "$TMUX_COMMAND" "" set-option -t "$SESSION" pane-border-status top
tmux_call "$TMUX_COMMAND" "" set-option -t "$SESSION" pane-border-format ' #{pane_title} '
tmux_call "$TMUX_COMMAND" "" select-window -t "$SESSION:1"
exec "$TMUX_COMMAND" attach-session -t "$SESSION"
```

- [ ] Run `tests/workspace-bootstrap.sh`, `bash -n bin/super-review tests/workspace-bootstrap.sh`, and `git diff --check`; expect all tests to pass without touching the live session.

- [ ] Commit:

```bash
atomic-commit "bin: port the local super-review launcher" -- bin/super-review tests/workspace-bootstrap.sh
```

---

## Task 6: Integrate installation, documentation, and full validation

**Files**

- Modify: `tests/workspace-bootstrap.sh`
- Modify: `install.sh`
- Modify: `README.md`

**Interfaces**

- Consumes: the installer's existing `link <source> <destination>` behavior.
- Produces: managed `$HOME/super-review.sh -> <checkout>/bin/super-review`, plus operator documentation for bootstrap and both launchers.

- [ ] Add and register this installer dry-run regression test:

```bash
test_installer_previews_super_review_link() {
  local home output
  home="$(new_home installer)"
  output="$(HOME="$home" "$ROOT/install.sh" --dry-run)"
  assert_contains "$output" \
    "[would link]    $home/super-review.sh -> $ROOT/bin/super-review" \
    "installer previews the managed super-review link"
  assert_missing "$home/super-review.sh" "installer dry run does not create the link"
}
run_test "previews the managed super-review link" test_installer_previews_super_review_link
```

The asserted line is:

```text
[would link]    <temporary-home>/super-review.sh -> <checkout>/bin/super-review
```

If the generated-agent validation needs a writable cache, keep it under the temporary home; do not run a non-dry installer from the worktree.

- [ ] Run only the new installer assertion; expect failure because `install.sh` does not mention `super-review`.

- [ ] Immediately after the `# --- CLI tools ---` heading in `install.sh`, add:

```bash
link "$REPO_ROOT/bin/super-review" "$HOME/super-review.sh"
```

- [ ] Update the README `Layout` table with:

```markdown
| `bin/super-review` | `~/super-review.sh` |
| `bin/workspace-tmux` | `~/bin/mosh-tmux` (installed by `workspace-init`, not `install.sh`) |
```

Then add a `## Workspace bootstrap and tmux` section containing the following operator-facing content:

````markdown
## Workspace bootstrap and tmux

Initialize the workflow checkout set on the current Mac:

```sh
bin/workspace-init --dry-run
bin/workspace-init
bin/workspace-init --workspace /another/work
```

The default root is `~/work`. Missing `workflow-openhuman`,
`workflow-medulla`, `workflow-tinyplace`, `workflow-opencompany`, and
`workflow-dashboard` repositories are cloned over SSH with recursive
submodules. Existing destinations are skipped without inspection or updates.
The command also installs `~/bin/mosh-tmux` as a link to
`bin/workspace-tmux`, backing up a conflicting destination under
`~/.config-backups/`.

On the Mac mini, `~/bin/mosh-tmux` creates or reuses the dedicated `mosh`
tmux server's `workspace` session. It provides six-pane windows for each
workflow repository plus `btop` and `shell`, reapplies the remote blue theme
and `C-z` prefix, and attaches. Override the server and session names with
`MOSH_TMUX_SERVER` and `MOSH_TMUX_SESSION`.

The local `~/super-review.sh` link is managed by `install.sh`. Running it
creates the five four-pane workflow windows, the mixed `libraries` window,
`btop`, Robot1 `cloud`, Mac mini, and shell windows. **It deliberately kills
and recreates any existing `super-review` tmux session.** Run
`~/super-review.sh --help` to review that warning without changing tmux state.
````

- [ ] Run the complete safe validation set:

```bash
tests/workspace-bootstrap.sh
bash -n install.sh bin/* claude/statusline-command.sh tests/workspace-bootstrap.sh
zsh -n zshrc
bin/check-skills
./install.sh --dry-run
git diff --check
```

Expect the integration suite's TAP plan to match its pass count, every syntax/validation command to exit zero, the installer preview to include `~/super-review.sh`, and no live tmux attach/kill command to execute.

- [ ] Review `git diff --stat` and `git status --short`; only `README.md`, `install.sh`, and `tests/workspace-bootstrap.sh` should be uncommitted in this task.

- [ ] Commit:

```bash
atomic-commit "docs: integrate workspace launchers" -- README.md install.sh tests/workspace-bootstrap.sh
```

---

## Plan Self-Review

- **Spec coverage:** Tasks 1–2 cover bootstrap arguments, exact clones, opaque existing destinations, dry-run, resume behavior, link idempotency, and backups. Tasks 3–5 cover every shared primitive, both complete window sets, exact working directories/remote commands, dedicated-server reuse, theme, prefix, dependency errors, nested-tmux refusal, and destructive local replacement. Task 6 covers installer ownership, README warnings, and all specified safe validation gates.
- **Placeholders:** Every production file has complete code, every task names concrete assertions and expected failures, and no deferred implementation marker remains.
- **Interface consistency:** Both launchers call the five exact helper signatures defined in Task 3; environment overrides and session/server names match the approved design and the tests.
- **Live-state safety:** All launcher behavior is exercised only through fake executables. The only installer invocation from the disposable worktree is `--dry-run`.
