#!/usr/bin/env bash
# Claude Code statusLine command
# Mirrors the Oh My Zsh "clean" theme (bright/bold colors for a terminal footer):
#   dir (git branch [#PR]) model | remaining-context%
# When the current branch has an open PR, the branch chunk becomes an OSC 8
# hyperlink to the PR URL (Cmd-click in iTerm2/Kitty/WezTerm).

input=$(cat)

dir=$(basename "$(pwd)")
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
session_id=$(echo "$input" | jq -r '.session_id // "nosession"')

# Git branch (skip optional locks)
git_branch_text=""
branch=""
if git -C "$(pwd)" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$(pwd)" symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$(pwd)" rev-parse --short HEAD 2>/dev/null)
fi

# PR detection — cached per (session, branch) for 30s
pr_number=""
pr_url=""
if [ -n "$branch" ] && command -v gh >/dev/null 2>&1; then
  safe_branch=$(printf '%s' "$branch" | tr '/:' '__')
  cache_file="/tmp/cc-statusline-pr-${session_id}-${safe_branch}"
  cache_max_age=30
  now=$(date +%s)
  use_cache=0
  if [ -f "$cache_file" ]; then
    mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)
    if [ $((now - mtime)) -lt "$cache_max_age" ]; then
      use_cache=1
    fi
  fi
  if [ "$use_cache" -eq 0 ]; then
    # Special case: branch named pr/<N> — look up PR by number directly.
    if [[ "$branch" =~ ^pr/([0-9]+)$ ]]; then
      pr_json=$(gh pr view "${BASH_REMATCH[1]}" --json number,url 2>/dev/null || true)
    else
      pr_json=$(gh pr view --json number,url 2>/dev/null || true)
    fi
    if [ -n "$pr_json" ]; then
      pr_number=$(echo "$pr_json" | jq -r '.number // empty')
      pr_url=$(echo "$pr_json" | jq -r '.url // empty')
    fi
    printf '%s|%s\n' "$pr_number" "$pr_url" > "$cache_file"
  else
    IFS='|' read -r pr_number pr_url < "$cache_file"
  fi
fi

# Build branch chunk (with optional PR suffix)
if [ -n "$branch" ]; then
  if [ -n "$pr_number" ]; then
    git_branch_text=" ($branch #$pr_number)"
  else
    git_branch_text=" ($branch)"
  fi
fi

# Wrap branch chunk in OSC 8 hyperlink if we have a PR URL (bright bold red, omz "clean" style)
git_branch_part=""
if [ -n "$git_branch_text" ]; then
  if [ -n "$pr_url" ]; then
    # OSC 8: \e]8;;URL\e\\TEXT\e]8;;\e\\
    git_branch_part=$(printf '\033[1;91m\033]8;;%s\033\\%s\033]8;;\033\\\033[0m' "$pr_url" "$git_branch_text")
  else
    git_branch_part=$(printf '\033[1;91m%s\033[0m' "$git_branch_text")
  fi
fi

# Model name (bright bold magenta)
model_part=""
if [ -n "$model" ]; then
  model_part=$(printf ' \033[1;95m%s\033[0m' "$model")
fi

# Remaining context (bright bold yellow)
ctx_part=""
if [ -n "$remaining_pct" ]; then
  ctx_part=$(printf ' | \033[1;93m%s%% left\033[0m' "$(printf '%.0f' "$remaining_pct")")
fi

# Build output: dir(git [#PR]) model | remaining% left   (bright bold cyan dir, like omz "clean" theme)
printf '\033[1;96m%s\033[0m%s%s%s' \
  "$dir" "$git_branch_part" "$model_part" "$ctx_part"
