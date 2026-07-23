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

# sentry_config <org-or-empty> <project-or-empty>
# Flags win over env; the API token is required.
sentry_config() {
  SENTRY_ORG_R="${1:-${SENTRY_ORG:-}}"
  SENTRY_PROJECT_R="${2:-${SENTRY_PROJECT:-}}"
  SENTRY_TOKEN_R="${SENTRY_AUTH_TOKEN:-}"
  local url="${SENTRY_URL:-https://sentry.io}"
  SENTRY_BASE="${url%/}/api/0"
  [ -n "$SENTRY_TOKEN_R" ] \
    || sentry_fail "SENTRY_AUTH_TOKEN is not set (needed for the Sentry API)"
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
