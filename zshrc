res() {
  local remote=upstream
  git remote get-url upstream >/dev/null 2>&1 || remote=origin
  git checkout main && git fetch "$remote" && git merge "$remote/main" \
    && git submodule update --init --recursive && clear
}

alias mrg="gf upstream && gm"
alias k="kubectl"
alias desk="cd ~/Desktop"
alias home="cd ~"
alias down="cd ~/Downloads"
alias ping8="ping 8.8.8.8"
alias agunt="agent --yolo"
alias gumini="gemini --yolo"
alias cudex="codex --yolo"
alias aliases="vim ~/.zshrc"
alias cleude="claude"
alias work="cd ~/work"

rust-clean() {
  local workspace="$HOME/work/"
  local dry_run=0
  [ "$1" = "--dry-run" ] && dry_run=1

  local manifest target found=0
  local -A seen_targets
  while IFS= read -r -d '' manifest; do
    target="${manifest:h}/target"
    [ -d "$target" ] || continue
    [ -z "${seen_targets[$target]-}" ] || continue
    seen_targets[$target]=1
    found=1

    if [ "$dry_run" -eq 1 ]; then
      echo "[dry-run] $target"
    else
      echo "[rm] $target"
      rm -rf "$target"
    fi
  done < <(rg --files -0 -uu \
    -g 'Cargo.toml' \
    -g '!**/.git/**' \
    -g '!**/node_modules/**' \
    -g '!**/target/**' \
    "$workspace" 2>/dev/null)

  if [ "$found" -eq 0 ]; then
    echo "No matching target directories found."
  elif [ "$dry_run" -eq 1 ]; then
    echo "Dry run only. Re-run with: human-clean"
  else
    echo "Done."
  fi
}

# PR triage — thin wrappers over the repo's `pr-sync` tool (bin/pr-sync),
# which checks the PR out into <repo>/worktrees/pr-<n>, merges the base
# branch, wires pushRemote to the fork, and launches the agent.

preem() {
  if [ -z "$1" ]; then
    echo "Usage: preem <pr-number> [review|fix|resolve_comments(default)]"
    return 1
  fi
  local pr="$1" extra
  case "${2:-resolve_comments}" in
    review)
      extra="Use the pr-reviewer agent to review PR #$pr and publish review comments. Do not push code changes." ;;
    fix)
      extra="Use the pr-reviewer agent to review PR #$pr and fix the issues. Then use the pr-manager-lite agent to push the changes to the PR." ;;
    *)
      extra="Use the pr-manager-lite agent to resolve the review comments on PR #$pr." ;;
  esac
  pr-sync "$pr" "$extra" claude
}

cream() {
  if [ -z "$1" ]; then
    echo "Usage: cream <pr-number>"
    return 1
  fi
  pr-sync "$1" "Use the pr-manager-lite agent to review and resolve the review comments on PR #$1." codex
}
