# Expose this repo's CLI tools (bin/, e.g. pr-fix) on PATH.
# Self-locating: resolves relative to this file, wherever the repo lives.
_workspace_bin="${${(%):-%x}:A:h}/bin"
case ":$PATH:" in
  *":$_workspace_bin:"*) ;;
  *) export PATH="$_workspace_bin:$PATH" ;;
esac
unset _workspace_bin

ocr() {
  local installer wrapper
  installer="$(command -v install-open-code-review)"
  wrapper="${installer:h}/ocr"
  "$wrapper" "$@"
}

res() {
  local remote=upstream
  git remote get-url upstream >/dev/null 2>&1 || remote=origin
  git checkout main && git fetch "$remote" && git merge "$remote/main" || return
  # Shallow submodules, with a full-depth retry when a gitlink is out of a
  # shallow fetch's reach — shared with worktree/pr-fix via `submodule-init`.
  # Set SUBMODULE_DEPTH=0 to skip the shallow attempt entirely.
  submodule-init || return
  clear
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

# Attach to each box's persistent tmux workspace (see bin/box).
alias df="box dragonfly"
alias mini="box mac-mini"
alias r1="box robot1"

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
    echo "Dry run only. Re-run with: rust-clean"
  else
    echo "Done."
  fi
}
