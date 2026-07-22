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

_pr_sync() {
  local pr="$1"
  
  # 1. Sync local main with upstream
  git checkout main && \
  git pull origin main && \
  git fetch upstream && \
  git merge upstream/main && \
  git submodule update --init --recursive || return 1

  # 2. Resolve the PR's head repo + branch
  local info head_repo head_branch local_branch
  info=$(gh pr view "$pr" -R tinyhumansai/openhuman \
    --json headRefName,headRepository,headRepositoryOwner) || return 1
  
  head_repo=$(echo "$info" | jq -r '.headRepositoryOwner.login + "/" + .headRepository.name')
  head_branch=$(echo "$info" | jq -r '.headRefName')
  local_branch="pr/$pr"

  echo "[preem] PR #$pr -> $head_repo:$head_branch (local: $local_branch)"

  # 3. Fetch PR branch from the fork
  git fetch "https://github.com/${head_repo}.git" \
    "+${head_branch}:${local_branch}" || return 1
  
  git checkout "$local_branch"

  # 4. Attempt merge main into PR branch, ignoring errors/conflicts
  echo "[preem] Attempting to merge main into $local_branch..."
  git merge main || echo "[!] Conflicts detected in PR #$pr, but continuing as requested."

  # 5. Set upstream + push remote to the PR's fork
  echo "[preem] Configuring upstream tracking for $head_repo..."

  local remote_name="remote-$pr"
  local remote_url="https://github.com/${head_repo}.git"

  # Prefer SSH remote if one already points at this fork (avoids https auth prompts on push)
  local existing_ssh
  existing_ssh=$(git remote -v | awk -v repo="$head_repo" '$2 ~ ("[:/]" repo "(\\.git)?$") && $3 == "(fetch)" {print $1; exit}')
  if [ -n "$existing_ssh" ]; then
    remote_name="$existing_ssh"
    echo "[preem] Reusing existing remote '$remote_name' -> $(git remote get-url "$remote_name")"
  else
    git remote add "$remote_name" "$remote_url" 2>/dev/null || \
      git remote set-url "$remote_name" "$remote_url"
  fi

  # Explicit refspec ensures refs/remotes/<remote>/<branch> is populated
  # (a bare `git fetch <remote> <branch>` only writes FETCH_HEAD in some git versions)
  git fetch "$remote_name" "+refs/heads/${head_branch}:refs/remotes/${remote_name}/${head_branch}" || {
    echo "[!] Failed to fetch $head_branch from $remote_name."
    return 1
  }

  # Track upstream (for pulls/status) and set pushRemote (so `git push` lands on the fork)
  if git branch --set-upstream-to="$remote_name/$head_branch" "$local_branch"; then
    git config "branch.${local_branch}.pushRemote" "$remote_name"
    git config "branch.${local_branch}.merge" "refs/heads/${head_branch}"
    echo "[preem] Upstream + pushRemote set to $remote_name/$head_branch"
  else
    echo "[!] Failed to set upstream. You may need to push manually."
    return 1
  fi
}

preem() {
  if [ -z "$1" ]; then
    echo "Usage: preem <pr-number> [review|fix|resolve_comments(default)]"
    return 1
  fi

  if [ "$2" = "review" ]; then
    action="review"
  elif [ "$2" = "fix" ]; then
    action="fix"
  else
    action="resolve_comments"
  fi


  if [ "$action" = "review" ]; then 
    _pr_sync "$1" && \  # sync the PR and set upstream + push remote to the PR's fork
    cleude "I've already checked out branch pr/$1 with main merged in and upstream tracking set. Use the pr-reviewer agent to review the PR #$1 and publish review comments."
  elif [ "$action" = "fix" ]; then
    _pr_sync "$1" && \  # sync the PR and set upstream + push remote to the PR's fork
    cleude "I've already checked out branch pr/$1 with main merged in and upstream tracking set. Use the pr-reviewer agent to review the PR #$1 and fix the issues. Then use the pr-manager-lite agent to push the changes to the PR."
  else
    _pr_sync "$1" && \  # sync the PR and set upstream + push remote to the PR's fork
    cleude "I've already checked out branch pr/$1 with main merged in and upstream tracking set. Use the pr-manager-lite agent to resolve the review comments on PR #$1."
  fi
}

cream() {
  if [ -z "$1" ]; then
    echo "Usage: cream <pr-number>"
    return 1
  fi
  _pr_sync "$1" && \
  cudex "I've already checked out branch pr/$1 with main merged in and upstream tracking set. Use the pr-manager-lite agent to review and resolve the review comments on PR #$1."
}
