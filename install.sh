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
"$REPO_ROOT/bin/check-open-source-state"

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

# Remove a shared skill link (skills/<name>) that has been deleted from the repo.
# The shared-skill loops below only create links; they never prune a skill whose
# canonical source is gone, so retired skills are cleaned up explicitly here.
remove_shared_skill_link() {
  local harness="$1" name="$2"
  local installed="$HOME/.$harness/skills/$name"
  local shared_source="$REPO_ROOT/skills/$name"

  if [ -L "$installed" ] && [ "$(readlink "$installed")" = "$shared_source" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[would remove] retired skill link $installed"
    else
      rm "$installed"
      echo "[unlink] retired skill $installed"
    fi
  fi
}

remove_shared_skill_link "claude" "using-superpowers"
remove_shared_skill_link "codex" "using-superpowers"
remove_shared_skill_link "claude" "brainstorming"
remove_shared_skill_link "codex" "brainstorming"

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

# --- Medulla workflows --------------------------------------------------------
# The whole store directory is one symlink onto workflows/, not a link per file.
# That direction matters: Medulla publishes a flow by writing a temporary file
# beside the target and renaming it into place, and `rename` replaces the *path*
# without following it. With a link per file, saving a shared flow from the TUI
# silently swapped its symlink for a regular file and the edit never reached this
# repository; a flow created from scratch simply landed in the account store and
# stayed there. Linking the directory puts the rename *inside* workflows/, so
# every flow Medulla writes — new or edited — is a change in this checkout.
#
# The cost is that the store no longer holds anything unshared: a machine-local
# flow written there is written here. That is the intent — this repository is
# where workflows live now — but it is why the adoption step below exists.
#
# The destination is per account, not per install. Medulla scopes everything it
# persists to `<root>/<account id>` and reads its user-global workflow store from
# `<root>/<account id>/workflows`; the root itself holds only account directories
# and the `active_user.toml` marker naming the live one. The flat
# `~/.medulla/workflows` this used to link into predates that split and is no
# longer read at all, which is how the shared flows became invisible to Medulla
# while their symlinks still looked perfectly healthy.
MEDULLA_ROOT="${MEDULLA_HOME:-$HOME/.medulla}"

# The active account, then every other account already on this machine — sharing
# a workflow only with whoever happens to be signed in now would drop it the
# next time the marker changes.
medulla_accounts() {
  local marker="$MEDULLA_ROOT/active_user.toml" active="" d name
  if [ -n "${MEDULLA_USER:-}" ]; then
    active="$MEDULLA_USER"
  elif [ -f "$marker" ]; then
    active="$(sed -n 's/^[[:space:]]*user_id[[:space:]]*=[[:space:]]*"\([^"]*\)".*$/\1/p' "$marker" | head -1)"
  fi
  # Nobody has signed in on this box yet. Pre-login state is real state and lives
  # under its own id, so the flows belong there just the same.
  [ -n "$active" ] || active="local"
  printf '%s\n' "$active"
  for d in "$MEDULLA_ROOT"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    [ "$name" != "$active" ] || continue
    # An account directory is one Medulla has homed: it carries the layered
    # config file. This is what keeps `bin/`, the legacy `workflows/`, and any
    # other stray directory at the root from being mistaken for an account.
    [ -f "$d/config.toml" ] || [ "$name" = "local" ] || continue
    printf '%s\n' "$name"
  done
}

# Take a real store directory into the repository before replacing it with the
# link. Anything in there that is not already one of ours is a flow Medulla wrote
# on this machine — either created in the TUI or saved over a per-file link by
# the rename described above — and swapping the directory out would file it away
# under ~/.config-backups where nothing reads it again. A name this repository
# already carries is left alone and reported: the two versions may genuinely
# differ, and picking a winner is a merge, not an install step.
medulla_adopt_workflows() {
  local dir="$1" f base
  [ -d "$dir" ] || return 0
  [ -L "$dir" ] && return 0
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    if [ -L "$f" ]; then continue; fi
    base="$(basename "$f")"
    if cmp -s "$f" "$REPO_ROOT/workflows/$base"; then
      : # already identical to the shared copy; the link supersedes it
    elif [ -e "$REPO_ROOT/workflows/$base" ]; then
      echo "[keep] $f differs from workflows/$base — resolve by hand, backup kept"
    elif [ "$DRY_RUN" -eq 1 ]; then
      echo "[would adopt]   workflows/$base <- $f"
    else
      cp "$f" "$REPO_ROOT/workflows/$base"
      echo "[adopt] workflows/$base <- $f"
    fi
  done
}

while IFS= read -r account; do
  [ -n "$account" ] || continue
  medulla_adopt_workflows "$MEDULLA_ROOT/$account/workflows"
  link "$REPO_ROOT/workflows" "$MEDULLA_ROOT/$account/workflows"
  # The config is merged rather than linked; see bin/medulla-config-merge for
  # why a symlink cannot survive Medulla saving its own settings.
  if [ "$DRY_RUN" -eq 1 ]; then
    "$REPO_ROOT/bin/medulla-config-merge" --dry-run \
      "$REPO_ROOT/medulla/config.toml" "$MEDULLA_ROOT/$account/config.toml"
  else
    "$REPO_ROOT/bin/medulla-config-merge" \
      "$REPO_ROOT/medulla/config.toml" "$MEDULLA_ROOT/$account/config.toml"
  fi
done < <(medulla_accounts)

# Retire the pre-account links. Only symlinks into this repository's workflows/
# are removed — an unmanaged file someone left there is Medulla's or theirs, not
# ours to delete, even though nothing reads it any more.
for f in "$MEDULLA_ROOT"/workflows/*.json; do
  [ -L "$f" ] || continue
  case "$(readlink "$f")" in
    "$REPO_ROOT"/workflows/*)
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "[would unlink]  $f (legacy pre-account location)"
      else
        rm -f "$f"
        echo "[unlink] $f (legacy pre-account location)"
      fi
      ;;
  esac
done

# --- git ----------------------------------------------------------------------
# ~/.gitconfig stays a local file: it holds the signing key, the GPG binary's
# path, and credential helpers pointing at Homebrew, none of which are portable
# to the Linux boxes. The shared, portable half is pulled in with include.path,
# which git evaluates in place — so appending it means the repo's values win over
# anything set earlier in the local file.
GITCONFIG_SHARED="$REPO_ROOT/gitconfig"
if [ ! -f "$GITCONFIG_SHARED" ]; then
  echo "[skip] missing source: $GITCONFIG_SHARED"
elif git config --global --get-all include.path 2>/dev/null | grep -qxF "$GITCONFIG_SHARED"; then
  echo "[ok]   ~/.gitconfig includes $GITCONFIG_SHARED"
elif [ "$DRY_RUN" -eq 1 ]; then
  echo "[would include] ~/.gitconfig -> $GITCONFIG_SHARED"
else
  git config --global --add include.path "$GITCONFIG_SHARED"
  echo "[include] ~/.gitconfig -> $GITCONFIG_SHARED"
fi

# The include cannot retire a setting it does not name, and a stale
# `format.pretty = oneline` in the local file is exactly the setting that made
# every `git log` print a hash and a subject and nothing else. Remove it only
# when it still holds that value — a deliberate custom format is left alone.
if [ "$(git config --global --get format.pretty 2>/dev/null || true)" = "oneline" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[would unset]   ~/.gitconfig format.pretty=oneline (shadows the shared log format)"
  else
    git config --global --unset-all format.pretty
    echo "[unset] ~/.gitconfig format.pretty=oneline (shadowed the shared log format)"
  fi
fi

# --- tmux --------------------------------------------------------------------
link "$REPO_ROOT/tmux.conf" "$HOME/.tmux.conf"

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

# --- Cloned repository remotes ------------------------------------------------
# Every TinyHumans clone and submodule should push to my fork and pull from the
# canonical repo, on every box. Non-fatal: a box with no clones, no network, or
# no fork for a given repo just reports and moves on.
echo
if [ "$DRY_RUN" -eq 1 ]; then
  "$REPO_ROOT/bin/repo-remotes" --dry-run || echo "[skip] repo remotes could not be checked"
else
  "$REPO_ROOT/bin/repo-remotes" || echo "[skip] repo remotes could not be updated"
fi

echo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run complete. Re-run without --dry-run to apply."
else
  echo "Done. Backups (if any) are in $BACKUP_DIR"
fi
