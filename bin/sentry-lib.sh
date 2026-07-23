#!/usr/bin/env bash
# sentry-lib.sh — shared helpers for the sentry-* agent tools. Sourced, not run.
#
# Provides Sentry config resolution, an authenticated Sentry Web API caller, and
# small utilities. The sentry-* report/issue/resolve tools use the API for
# structured, agent-friendly JSON (sentry-cli does not expose issue data in an
# agent-friendly form); `sentry-release` wraps `sentry-cli` for release ops.
# All read the same config sentry-cli reads:
#   SENTRY_AUTH_TOKEN  (required for the API)
#   SENTRY_ORG         (default org; override with --org)
#   SENTRY_PROJECT     (default project; override with --project)
#   SENTRY_URL         (base URL; default https://sentry.io — set for self-hosted)

sentry_fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

sentry_require() {
  local b
  for b in "$@"; do
    command -v "$b" >/dev/null 2>&1 || sentry_fail "missing required tool: $b"
  done
}

# Resolved config (populated by sentry_config).
SENTRY_BASE=""
SENTRY_ORG_R=""
SENTRY_PROJECT_R=""
SENTRY_TOKEN_R=""

# --- Repo-aware resolution -------------------------------------------------

# sentry_repo_slug — the current repo's canonical owner/name (upstream preferred,
# else origin); empty when not in a GitHub repo.
sentry_repo_slug() {
  local url
  url=$(git remote get-url upstream 2>/dev/null || git remote get-url origin 2>/dev/null) || return 0
  printf '%s' "$url" | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##'
}

# sentry_map_file — the repo->project map: lines of "owner/repo<TAB>org<TAB>project".
sentry_map_file() { printf '%s' "${SENTRY_REPO_MAP:-$HOME/.config/sentry/repos.tsv}"; }

# sentry_map_lookup <slug> — the matching "slug<TAB>org<TAB>project" line, if any.
sentry_map_lookup() {
  local f; f="$(sentry_map_file)"
  [ -f "$f" ] || return 0
  awk -F'\t' -v s="$1" '!/^[[:space:]]*#/ && $1 == s { print; exit }' "$f"
}

# sentry_ini_get <file> <section> <key> — read a value from a .sentryclirc INI file.
sentry_ini_get() {
  local file="$1" section="[$2]" key="$3"
  [ -f "$file" ] || return 0
  awk -v sect="$section" -v key="$key" '
    /^[[:space:]]*\[/ { insect = (index($0, sect) > 0); next }
    insect && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") {
      sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit
    }
  ' "$file"
}

# sentry_config <org-or-empty> <project-or-empty>
# Resolves org/project/token/url. Precedence for org/project:
#   flags > env > repo .sentryclirc > repo->project map > ~/.sentryclirc
# so the sentry-* helpers "just work" from inside a bound repo. A token is
# required (env or a .sentryclirc [auth] token).
sentry_config() {
  local flag_org="${1:-}" flag_project="${2:-}"
  local root rc_repo="" rc_home="$HOME/.sentryclirc"
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$root" ] && [ -f "$root/.sentryclirc" ] && rc_repo="$root/.sentryclirc"

  SENTRY_ORG_R="${flag_org:-${SENTRY_ORG:-}}"
  SENTRY_PROJECT_R="${flag_project:-${SENTRY_PROJECT:-}}"
  if [ -n "$rc_repo" ]; then
    [ -n "$SENTRY_ORG_R" ]     || SENTRY_ORG_R="$(sentry_ini_get "$rc_repo" defaults org)"
    [ -n "$SENTRY_PROJECT_R" ] || SENTRY_PROJECT_R="$(sentry_ini_get "$rc_repo" defaults project)"
  fi
  if [ -z "$SENTRY_ORG_R" ] || [ -z "$SENTRY_PROJECT_R" ]; then
    local slug mapline; slug="$(sentry_repo_slug)"
    if [ -n "$slug" ]; then
      mapline="$(sentry_map_lookup "$slug")"
      if [ -n "$mapline" ]; then
        [ -n "$SENTRY_ORG_R" ]     || SENTRY_ORG_R="$(printf '%s' "$mapline" | cut -f2)"
        [ -n "$SENTRY_PROJECT_R" ] || SENTRY_PROJECT_R="$(printf '%s' "$mapline" | cut -f3)"
      fi
    fi
  fi
  if [ -f "$rc_home" ]; then
    [ -n "$SENTRY_ORG_R" ]     || SENTRY_ORG_R="$(sentry_ini_get "$rc_home" defaults org)"
    [ -n "$SENTRY_PROJECT_R" ] || SENTRY_PROJECT_R="$(sentry_ini_get "$rc_home" defaults project)"
  fi

  SENTRY_TOKEN_R="${SENTRY_AUTH_TOKEN:-}"
  [ -n "$SENTRY_TOKEN_R" ] || { [ -n "$rc_repo" ] && SENTRY_TOKEN_R="$(sentry_ini_get "$rc_repo" auth token)"; }
  [ -n "$SENTRY_TOKEN_R" ] || { [ -f "$rc_home" ] && SENTRY_TOKEN_R="$(sentry_ini_get "$rc_home" auth token)"; }

  local url="${SENTRY_URL:-}"
  [ -n "$url" ] || { [ -n "$rc_repo" ] && url="$(sentry_ini_get "$rc_repo" defaults url)"; }
  [ -n "$url" ] || { [ -f "$rc_home" ] && url="$(sentry_ini_get "$rc_home" defaults url)"; }
  [ -n "$url" ] || url="https://sentry.io"
  SENTRY_BASE="${url%/}/api/0"

  [ -n "$SENTRY_TOKEN_R" ] \
    || sentry_fail "no Sentry auth token (set SENTRY_AUTH_TOKEN, or add an [auth] token to ~/.sentryclirc)"
}

sentry_need_project() {
  [ -n "$SENTRY_ORG_R" ] \
    || sentry_fail "no org: pass --org or set SENTRY_ORG"
  [ -n "$SENTRY_PROJECT_R" ] \
    || sentry_fail "no project: pass --project or set SENTRY_PROJECT"
}

sentry_need_org() {
  [ -n "$SENTRY_ORG_R" ] || sentry_fail "no org: pass --org or set SENTRY_ORG"
}

# sentry_urlencode <string>
sentry_urlencode() { jq -rn --arg s "$1" '$s | @uri'; }

# sentry_api <METHOD> <PATH-starting-with-slash> [JSON_BODY]
# Prints the response body; fails on HTTP >= 400 with the API's error message.
sentry_api() {
  local method="$1" path="$2" body="${3:-}"
  local url="$SENTRY_BASE$path" tmp status
  tmp="$(mktemp)"
  local -a args=(
    -sS -X "$method"
    -H "Authorization: Bearer $SENTRY_TOKEN_R"
    -H "Content-Type: application/json"
    -o "$tmp" -w '%{http_code}'
  )
  [ -z "$body" ] || args+=(-d "$body")
  status="$(curl "${args[@]}" "$url")" \
    || { rm -f "$tmp"; sentry_fail "curl failed: $method $url"; }
  if [ "$status" -ge 400 ]; then
    local msg; msg="$(jq -r '.detail // .error // .message // empty' "$tmp" 2>/dev/null)"
    rm -f "$tmp"
    sentry_fail "Sentry API $method $path -> HTTP $status${msg:+: $msg}"
  fi
  cat "$tmp"; rm -f "$tmp"
}

# sentry_issue_id <numeric-id-or-SHORT-ID>
# Echoes the numeric issue id, resolving a human short id via org issue search.
sentry_issue_id() {
  local ref="$1"
  [ -n "$ref" ] || sentry_fail "empty issue id"
  case "$ref" in
    *[!0-9]*)
      sentry_need_org
      local out id
      out="$(sentry_api GET "/organizations/$SENTRY_ORG_R/issues/?limit=1&query=$(sentry_urlencode "$ref")")"
      id="$(jq -r '.[0].id // empty' <<<"$out")"
      [ -n "$id" ] || sentry_fail "no issue found for '$ref'"
      printf '%s' "$id" ;;
    *) printf '%s' "$ref" ;;
  esac
}

# Guard: this file is a library; running it directly is a no-op.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'sentry-lib.sh is a sourced library; use the sentry-* commands.\n' >&2
  exit 0
fi
