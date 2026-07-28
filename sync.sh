#!/usr/bin/env bash
# Syncs every remote box to origin/main and reinstalls the config there.
#
#   ./sync.sh              sync all boxes
#   ./sync.sh --check      report each box's HEAD without changing anything
#   ./sync.sh dragonfly    sync only the named box(es)
#
# Each box is pulled with --rebase and autostash, so machine-local tracked edits
# (e.g. claude/settings.json) survive the update instead of blocking it. Remote
# commands run through a login shell because the non-interactive PATH on some
# boxes cannot find rg and other tools install.sh requires. Pushes local commits
# first when the current checkout is ahead of origin.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

HOSTS=(
  "enamakel@dragonfly"
  "enamakel@mac-mini"
  "droid@robot1.digital.ocean"
)
REMOTE_PATH="~/work/workspace"

CHECK_ONLY=0
SELECTED=()

while [ $# -gt 0 ]; do
  case "$1" in
    --check)
      CHECK_ONLY=1
      shift
      ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      printf '[FAIL] unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
    *)
      SELECTED+=("$1")
      shift
      ;;
  esac
done

# A bare name selects the matching host entry, so `./sync.sh mac-mini` works.
if [ "${#SELECTED[@]}" -gt 0 ]; then
  MATCHED=()
  for want in "${SELECTED[@]}"; do
    found=""
    for host in "${HOSTS[@]}"; do
      case "$host" in
        "$want"|*"@$want"|"$want"@*) found="$host"; break ;;
      esac
    done
    [ -n "$found" ] || { printf '[FAIL] unknown box: %s\n' "$want" >&2; exit 1; }
    MATCHED+=("$found")
  done
  HOSTS=("${MATCHED[@]}")
fi

FAILED=()

if [ "$CHECK_ONLY" -eq 0 ]; then
  LOCAL_AHEAD=$(git -C "$REPO_ROOT" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)
  if [ "$LOCAL_AHEAD" -gt 0 ]; then
    printf '=== pushing %s local commit(s) first\n' "$LOCAL_AHEAD"
    git -C "$REPO_ROOT" push origin HEAD
  fi
fi

for host in "${HOSTS[@]}"; do
  printf '=== %s\n' "$host"

  if [ "$CHECK_ONLY" -eq 1 ]; then
    ssh "$host" "cd $REMOTE_PATH && git fetch -q origin && git log --oneline -1 && git status --short" \
      || FAILED+=("$host")
    continue
  fi

  if ssh "$host" "cd $REMOTE_PATH && bash -lc '
      set -e
      git -c rebase.autoStash=true pull --rebase
      ./install.sh >/dev/null
      git log --oneline -1
    '"; then
    printf '[ok]   %s\n' "$host"
  else
    printf '[FAIL] %s\n' "$host" >&2
    FAILED+=("$host")
  fi
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  printf '\n%d of %d box(es) failed: %s\n' \
    "${#FAILED[@]}" "${#HOSTS[@]}" "${FAILED[*]}" >&2
  exit 1
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  printf '\n%d box(es) reachable. Local: %s\n' \
    "${#HOSTS[@]}" "$(git -C "$REPO_ROOT" log --oneline -1)"
else
  printf '\n%d box(es) synchronized.\n' "${#HOSTS[@]}"
fi
