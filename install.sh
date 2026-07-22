#!/usr/bin/env bash
# Symlink-installs the config in this repo into $HOME.
#
# Agent-friendly: non-interactive, idempotent, safe to re-run.
#   ./install.sh            apply (backs up anything it replaces)
#   ./install.sh --dry-run  show what would happen, change nothing
#
# Every managed file in $HOME becomes a symlink pointing back into this
# repo, so editing either side edits the same file and `git diff` in the
# repo shows config drift.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

BACKUP_DIR="$HOME/.config-backups/workspace-$(date +%Y%m%d-%H%M%S)"

case "$REPO_ROOT" in
  */worktrees/*)
    echo "WARNING: running from a git worktree ($REPO_ROOT)."
    echo "Symlinks will break when the worktree is removed. Run from the primary checkout."
    ;;
esac

link() {
  local src="$1" dest="$2"

  if [ ! -e "$src" ]; then
    echo "[skip] missing source: $src"
    return
  fi

  # Already correct?
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "[ok]   $dest"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      echo "[would replace] $dest -> $src (backing up old)"
    else
      echo "[would link]    $dest -> $src"
    fi
    return
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dest" "$BACKUP_DIR/$(basename "$dest")"
    echo "[backup] $dest -> $BACKUP_DIR/"
  fi

  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  echo "[link] $dest -> $src"
}

# --- Claude Code global config ------------------------------------------------
link "$REPO_ROOT/claude/CLAUDE.md"              "$HOME/.claude/CLAUDE.md"
link "$REPO_ROOT/claude/settings.json"          "$HOME/.claude/settings.json"
link "$REPO_ROOT/claude/mcp.json"               "$HOME/.claude/mcp.json"
link "$REPO_ROOT/claude/statusline-command.sh"  "$HOME/.claude/statusline-command.sh"

# Agents: one symlink per .md file so Claude Code can still drop new files
# into ~/.claude/agents without touching the repo.
for f in "$REPO_ROOT"/claude/agents/*.md; do
  [ -e "$f" ] || continue
  link "$f" "$HOME/.claude/agents/$(basename "$f")"
done

# Skills: one symlink per skill directory.
for d in "$REPO_ROOT"/claude/skills/*/; do
  [ -d "$d" ] || continue
  d="${d%/}"
  link "$d" "$HOME/.claude/skills/$(basename "$d")"
done

# --- zsh ----------------------------------------------------------------------
# zsh/zshrc holds only our custom functions/aliases. ~/.zshrc stays a local,
# machine-specific file (oh-my-zsh, PATH exports, installer snippets) that
# loads the repo file via a marker line we ensure is present.
ensure_zshrc_loader() {
  local rc="$HOME/.zshrc"
  local marker="# workspace-custom (managed by install.sh)"
  local line="[ -f \"$REPO_ROOT/zsh/zshrc\" ] && source \"$REPO_ROOT/zsh/zshrc\""

  if [ -f "$rc" ] && grep -qF "$marker" "$rc"; then
    echo "[ok]   $rc sources repo zshrc"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[would append] loader line to $rc"
    return
  fi
  printf '\n%s\n%s\n' "$marker" "$line" >> "$rc"
  echo "[append] loader line -> $rc"
}
ensure_zshrc_loader

link "$REPO_ROOT/zsh/zshenv"  "$HOME/.zshenv"

echo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run complete. Re-run without --dry-run to apply."
else
  echo "Done. Backups (if any) are in $BACKUP_DIR"
fi
