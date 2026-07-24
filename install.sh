#!/usr/bin/env bash
# Symlink-installs the config in this repo into $HOME.
#
# Agent-friendly: non-interactive, idempotent, safe to re-run.
#   ./install.sh            apply (backs up anything it replaces)
#   ./install.sh --dry-run  show what would happen, change nothing
#
# Most managed files become symlinks pointing into this repo. Shared agents are
# rendered into a durable user cache, then linked into each harness.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

BACKUP_DIR="$HOME/.config-backups/workspace-$(date +%Y%m%d-%H%M%S)"
AGENT_BUILD_ROOT="$HOME/.config/workspace/generated-agents"

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

# --- Shared agents ------------------------------------------------------------
# Validate during previews; on apply, render native Claude and Codex files into
# a durable user cache. Build before changing links so missing tooling or
# invalid metadata fails the installation early.
if [ "$DRY_RUN" -eq 1 ]; then
  "$REPO_ROOT/bin/build-agents" --check
  echo "[would build] shared agents -> $AGENT_BUILD_ROOT"
else
  "$REPO_ROOT/bin/build-agents" --output-root "$AGENT_BUILD_ROOT"
fi
"$REPO_ROOT/bin/check-skills"

# Remove retired shared agents from the generated cache and harness directories.
# Destination files are removed only when they are our exact generated symlinks.
remove_retired_agent() {
  local name="$1" harness="$2" extension="$3"
  local generated="$AGENT_BUILD_ROOT/$harness/agents/$name.$extension"
  local installed="$HOME/.$harness/agents/$name.$extension"

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -e "$generated" ] || [ -L "$generated" ]; then
      echo "[would remove] retired generated agent $generated"
    fi
    if [ -L "$installed" ] && [ "$(readlink "$installed")" = "$generated" ]; then
      echo "[would remove] retired agent link $installed"
    fi
    return
  fi

  if [ -L "$installed" ] && [ "$(readlink "$installed")" = "$generated" ]; then
    rm "$installed"
    echo "[unlink] retired agent $installed"
  fi
  if [ -e "$generated" ] || [ -L "$generated" ]; then
    rm "$generated"
    echo "[remove] retired generated agent $generated"
  fi
}

remove_retired_agent "ai-engineer" "claude" "md"
remove_retired_agent "ai-engineer" "codex" "toml"

# --- Shared agent rules -------------------------------------------------------
# One canonical RULES.md is symlinked into every agent's instructions file so
# claude, codex, and opencode always share the same Local Workflow Preferences.
# Edit RULES.md and re-run to update all of them at once.
link "$REPO_ROOT/RULES.md"  "$HOME/.claude/CLAUDE.md"
link "$REPO_ROOT/RULES.md"  "$HOME/.codex/AGENTS.md"
link "$REPO_ROOT/RULES.md"  "$HOME/.codex/CODEX.md"
link "$REPO_ROOT/RULES.md"  "$HOME/.config/opencode/AGENTS.md"

# --- Claude Code global config ------------------------------------------------
link "$REPO_ROOT/claude/settings.json"          "$HOME/.claude/settings.json"
link "$REPO_ROOT/claude/mcp.json"               "$HOME/.claude/mcp.json"
link "$REPO_ROOT/claude/statusline-command.sh"  "$HOME/.claude/statusline-command.sh"

remove_legacy_skill_link() {
  local harness="$1" name="$2"
  local installed="$HOME/.$harness/skills/$name"
  local legacy_source="$REPO_ROOT/$harness/skills/$name"

  if [ -L "$installed" ] && [ "$(readlink "$installed")" = "$legacy_source" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[would remove] legacy skill link $installed"
    else
      rm "$installed"
      echo "[unlink] legacy skill $installed"
    fi
  fi
}

remove_legacy_skill_link "claude" "humanizer"
remove_legacy_skill_link "claude" "solana-dev"
remove_legacy_skill_link "claude" "tiny-place-—-the-social-economy-for-ai-agents"
remove_legacy_skill_link "claude" "tinyplace"
remove_legacy_skill_link "codex" "tinyplace"

# Keep one symlink per generated file so Claude Code can still drop local files
# into ~/.claude/agents.
LEGACY_AI_AGENT="$HOME/.claude/agents/engineering-ai-engineer.md"
LEGACY_AI_SOURCE="$REPO_ROOT/claude/agents/engineering-ai-engineer.md"
if [ -L "$LEGACY_AI_AGENT" ] && [ "$(readlink "$LEGACY_AI_AGENT")" = "$LEGACY_AI_SOURCE" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[would remove] legacy agent link $LEGACY_AI_AGENT"
  else
    rm "$LEGACY_AI_AGENT"
    echo "[unlink] legacy agent $LEGACY_AI_AGENT"
  fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
  for d in "$REPO_ROOT"/agents/*/; do
    [ -d "$d" ] || continue
    name=$(basename "${d%/}")
    echo "[would link]    $HOME/.claude/agents/$name.md -> $AGENT_BUILD_ROOT/claude/agents/$name.md"
  done
else
  for f in "$AGENT_BUILD_ROOT"/claude/agents/*.md; do
    [ -e "$f" ] || continue
    link "$f" "$HOME/.claude/agents/$(basename "$f")"
  done
fi

# Skills: one canonical directory linked into both supported harnesses.
for d in "$REPO_ROOT"/skills/*/; do
  [ -d "$d" ] || continue
  d="${d%/}"
  link "$d" "$HOME/.claude/skills/$(basename "$d")"
done

# --- CLI tools ----------------------------------------------------------------
# bin/ is exposed on PATH by the repo zshrc (sourced from ~/.zshrc), not by
# symlinks. Clean up any ~/.local/bin links from the old scheme.
link "$REPO_ROOT/bin/super-review" "$HOME/super-review.sh"

for f in "$REPO_ROOT"/bin/*; do
  [ -f "$f" ] || continue
  dest="$HOME/.local/bin/$(basename "$f")"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$f" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[would remove] legacy link $dest"
    else
      rm "$dest"
      echo "[unlink] legacy $dest (bin/ is on PATH via zshrc)"
    fi
  fi
done

# --- Codex global config ------------------------------------------------------
# AGENTS.md / CODEX.md are linked from the shared rules block above.
# config.toml is deliberately NOT synced: it mixes machine state (project
# trust list, marketplace caches) with at least one embedded API key.
link "$REPO_ROOT/codex/hooks.json"  "$HOME/.codex/hooks.json"

# Agents: generated from the same shared sources as Claude agents.
if [ "$DRY_RUN" -eq 1 ]; then
  for d in "$REPO_ROOT"/agents/*/; do
    [ -d "$d" ] || continue
    name=$(basename "${d%/}")
    echo "[would link]    $HOME/.codex/agents/$name.toml -> $AGENT_BUILD_ROOT/codex/agents/$name.toml"
  done
else
  for f in "$AGENT_BUILD_ROOT"/codex/agents/*.toml; do
    [ -e "$f" ] || continue
    link "$f" "$HOME/.codex/agents/$(basename "$f")"
  done
fi

for d in "$REPO_ROOT"/skills/*/; do
  [ -d "$d" ] || continue
  d="${d%/}"
  link "$d" "$HOME/.codex/skills/$(basename "$d")"
done

# --- opencode global config ---------------------------------------------------
# AGENTS.md is linked from the shared rules block above.
# opencode.jsonc and the node_modules/package.json alongside it are local,
# gitignored machine state and are deliberately NOT synced.

# --- zsh ----------------------------------------------------------------------
# zshrc holds only our custom functions/aliases. ~/.zshrc stays a local,
# machine-specific file (oh-my-zsh, PATH exports, installer snippets) that
# loads the repo file via a marker line we ensure is present and current.
ensure_zshrc_loader() {
  local rc="$HOME/.zshrc"
  local marker="# workspace-custom (managed by install.sh)"
  local line="[ -f \"$REPO_ROOT/zshrc\" ] && source \"$REPO_ROOT/zshrc\""

  if [ -f "$rc" ] && grep -qF "$line" "$rc"; then
    echo "[ok]   $rc sources repo zshrc"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[would update] loader line in $rc"
    return
  fi
  # Drop any stale marker + following line, then append the current pair.
  if [ -f "$rc" ] && grep -qF "$marker" "$rc"; then
    sed -i '' "/^# workspace-custom (managed by install.sh)\$/{N;d;}" "$rc"
  fi
  printf '\n%s\n%s\n' "$marker" "$line" >> "$rc"
  echo "[update] loader line -> $rc"
}
ensure_zshrc_loader

echo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run complete. Re-run without --dry-run to apply."
else
  echo "Done. Backups (if any) are in $BACKUP_DIR"
fi
