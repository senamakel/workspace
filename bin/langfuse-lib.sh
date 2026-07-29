#!/usr/bin/env bash
# langfuse-lib.sh — shared helpers for the langfuse-* agent tools. Sourced, not run.
#
# Provides Langfuse environment resolution, an authenticated caller for the
# Langfuse public API, project-preset (trace-name) filtering, and shared jq
# helpers that flatten Langfuse's free-form input/output payloads into text an
# agent can read. The langfuse MCP server covers prompts, datasets, scores and
# evaluators but exposes no session/trace/observation reads — that gap is what
# these tools fill.
#
# Config, in precedence order:
#   flags (--env <alias>, --base-url/--public-key/--secret-key)
#   LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY [+ LANGFUSE_BASE_URL] in the env
#   the alias named by LANGFUSE_ENV, looked up in the env map
#   the alias `default` in the env map, else its only entry if it has just one
#
# Env map: ~/.config/langfuse/envs.tsv (override with LANGFUSE_ENVS), lines of
#   alias<TAB>base-url<TAB>public-key<TAB>secret-key
# A public-key field of `@/path/to/file` instead reads LANGFUSE_PUBLIC_KEY /
# LANGFUSE_SECRET_KEY (and LANGFUSE_BASE_URL, when base-url is `-`) out of that
# JSON or dotenv file, so deployment secrets stay in one place and are never
# copied into a second file. `#` starts a comment.
#
# Project map: ~/.config/langfuse/projects.tsv (override LANGFUSE_PROJECTS),
# lines of `alias<TAB>trace-name-regex[<TAB>tag]`. A Langfuse project holds every
# workload for one environment, so "which product is this" is a trace-name
# question, not a credentials question; `--project` applies the regex.

lf_fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

lf_require() {
  local b
  for b in "$@"; do
    command -v "$b" >/dev/null 2>&1 || lf_fail "missing required tool: $b"
  done
}

# Resolved config (populated by lf_config).
LF_BASE=""
LF_PK=""
LF_SK=""
LF_ENV_R=""

lf_envs_file()     { printf '%s' "${LANGFUSE_ENVS:-$HOME/.config/langfuse/envs.tsv}"; }
lf_projects_file() { printf '%s' "${LANGFUSE_PROJECTS:-$HOME/.config/langfuse/projects.tsv}"; }

# lf_env_lines — the env map's non-comment, non-blank lines.
lf_env_lines() {
  local f; f="$(lf_envs_file)"
  [ -f "$f" ] || return 0
  awk -F'\t' 'NF >= 2 && !/^[[:space:]]*#/ && $1 != ""' "$f"
}

# lf_env_lookup <alias> — that alias's line from the env map, if any.
lf_env_lookup() { lf_env_lines | awk -F'\t' -v a="$1" '$1 == a { print; exit }'; }

# lf_env_aliases — every configured alias, one per line.
lf_env_aliases() { lf_env_lines | cut -f1; }

# lf_secret_from_file <path> <KEY> — read KEY out of a JSON or dotenv file.
lf_secret_from_file() {
  local file="$1" key="$2"
  [ -f "$file" ] || lf_fail "secret source not found: $file"
  case "$file" in
    *.json)
      jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null ;;
    *)
      # dotenv / plain KEY=VALUE; ignore commented lines and strip quotes.
      awk -F= -v k="$key" '
        /^[[:space:]]*#/ { next }
        {
          sub(/^[[:space:]]*(export[[:space:]]+)?/, "")
          if (index($0, k "=") == 1) {
            sub(/^[^=]*=/, "")
            gsub(/^["'"'"'[:space:]]+|["'"'"'[:space:]]+$/, "")
            print; exit
          }
        }' "$file" ;;
  esac
}

# lf_apply_env_line <line> — populate LF_BASE/LF_PK/LF_SK from an env map line.
lf_apply_env_line() {
  local line="$1" base pk sk src
  base="$(printf '%s' "$line" | cut -f2)"
  pk="$(printf '%s' "$line" | cut -f3)"
  sk="$(printf '%s' "$line" | cut -f4)"
  case "$pk" in
    @*)
      src="${pk#@}"
      pk="$(lf_secret_from_file "$src" LANGFUSE_PUBLIC_KEY)"
      sk="$(lf_secret_from_file "$src" LANGFUSE_SECRET_KEY)"
      [ "$base" = "-" ] && base="$(lf_secret_from_file "$src" LANGFUSE_BASE_URL)"
      [ -n "$pk" ] && [ -n "$sk" ] \
        || lf_fail "no LANGFUSE_PUBLIC_KEY/LANGFUSE_SECRET_KEY in $src" ;;
  esac
  LF_BASE="${base%/}"; LF_PK="$pk"; LF_SK="$sk"
}

# lf_config <alias-or-empty> [base-url] [public-key] [secret-key]
# Resolves the Langfuse instance and credentials to talk to.
lf_config() {
  local alias="${1:-}" f_base="${2:-}" f_pk="${3:-}" f_sk="${4:-}"
  local line

  if [ -n "$f_pk" ] || [ -n "$f_sk" ]; then
    [ -n "$f_pk" ] && [ -n "$f_sk" ] \
      || lf_fail "--public-key and --secret-key must be given together"
    LF_BASE="${f_base:-${LANGFUSE_BASE_URL:-}}"; LF_PK="$f_pk"; LF_SK="$f_sk"
    LF_ENV_R="(flags)"
  elif [ -n "$alias" ]; then
    line="$(lf_env_lookup "$alias")"
    [ -n "$line" ] || lf_fail "unknown Langfuse env '$alias' (configured: $(lf_env_aliases | paste -sd, - 2>/dev/null || true); see $(lf_envs_file))"
    lf_apply_env_line "$line"; LF_ENV_R="$alias"
  elif [ -n "${LANGFUSE_PUBLIC_KEY:-}" ] && [ -n "${LANGFUSE_SECRET_KEY:-}" ]; then
    LF_BASE="${LANGFUSE_BASE_URL:-}"; LF_PK="$LANGFUSE_PUBLIC_KEY"; LF_SK="$LANGFUSE_SECRET_KEY"
    LF_ENV_R="(env)"
  elif [ -n "${LANGFUSE_ENV:-}" ]; then
    line="$(lf_env_lookup "$LANGFUSE_ENV")"
    [ -n "$line" ] || lf_fail "LANGFUSE_ENV='$LANGFUSE_ENV' is not in $(lf_envs_file)"
    lf_apply_env_line "$line"; LF_ENV_R="$LANGFUSE_ENV"
  else
    line="$(lf_env_lookup default)"
    if [ -z "$line" ] && [ "$(lf_env_lines | wc -l | tr -d ' ')" = "1" ]; then
      line="$(lf_env_lines)"
    fi
    [ -n "$line" ] \
      || lf_fail "no Langfuse env resolved: pass --env <alias>, set LANGFUSE_ENV, or add entries to $(lf_envs_file) (see \`langfuse-env --help\`)"
    lf_apply_env_line "$line"; LF_ENV_R="$(printf '%s' "$line" | cut -f1)"
  fi

  [ -n "$f_base" ] && LF_BASE="${f_base%/}"
  [ -n "$LF_BASE" ] || lf_fail "no Langfuse base URL (set LANGFUSE_BASE_URL or --base-url)"
  [ -n "$LF_PK" ] && [ -n "$LF_SK" ] \
    || lf_fail "no Langfuse credentials for '$LF_ENV_R'"
}

# lf_project_pattern <alias> — the trace-name regex a project alias maps to.
lf_project_pattern() {
  local f alias="$1" line
  [ -n "$alias" ] || return 0
  f="$(lf_projects_file)"
  if [ -f "$f" ]; then
    line="$(awk -F'\t' -v a="$alias" '!/^[[:space:]]*#/ && $1 == a { print; exit }' "$f")"
    [ -n "$line" ] && { printf '%s' "$line" | cut -f2; return 0; }
  fi
  # No map entry: treat the alias itself as the pattern, so --project medulla
  # still does the obvious thing on a box with no project map.
  printf '%s' "$alias"
}

lf_urlencode() { jq -rn --arg s "$1" '$s | @uri'; }

# lf_iso <spec> — an ISO-8601 UTC timestamp from `24h`, `7d`, `30m`, or a date
# already in ISO form (passed through). Works on both BSD and GNU date.
lf_iso() {
  local spec="$1" n unit
  case "$spec" in
    ''|*[!0-9]*[!hdmw]) : ;;
  esac
  if printf '%s' "$spec" | grep -Eq '^[0-9]+[mhdw]$'; then
    n="${spec%[mhdw]}"; unit="${spec##*[0-9]}"
    case "$unit" in m) unit=M ;; h) unit=H ;; d) unit=d ;; w) unit=w ;; esac
    if date -u -v-1d +%s >/dev/null 2>&1; then
      date -u -v-"${n}${unit}" +%Y-%m-%dT%H:%M:%SZ
    else
      local gnu
      case "$unit" in M) gnu="minutes" ;; H) gnu="hours" ;; d) gnu="days" ;; w) gnu="weeks" ;; esac
      date -u -d "-$n $gnu" +%Y-%m-%dT%H:%M:%SZ
    fi
  else
    printf '%s' "$spec"
  fi
}

# lf_api <PATH-starting-with-slash>
# GETs the Langfuse public API and prints the body; fails on HTTP >= 400.
lf_api() {
  # Note: a single `local` expands every word before it assigns any of them, so
  # `url` must be built on its own line.
  local path="$1" url tmp status msg
  url="$LF_BASE/api/public${path}"
  tmp="$(mktemp)"
  status="$(curl -sS -u "$LF_PK:$LF_SK" -H 'Accept: application/json' \
                 -o "$tmp" -w '%{http_code}' "$url")" \
    || { rm -f "$tmp"; lf_fail "curl failed: GET $url"; }
  if [ "$status" -ge 400 ]; then
    msg="$(jq -r '.message // .error // empty' "$tmp" 2>/dev/null)"
    rm -f "$tmp"
    lf_fail "Langfuse API GET $path -> HTTP $status${msg:+: $msg}"
  fi
  cat "$tmp"; rm -f "$tmp"
}

# lf_api_paged <PATH-without-page/limit> <total-wanted>
# Walks pages until <total-wanted> records are collected (or the data runs out),
# printing one JSON array. The path may already carry query params.
lf_api_paged() {
  local path="$1" want="$2" sep page=1 per got=0 body n pages acc
  case "$path" in *\?*) sep='&' ;; *) sep='?' ;; esac
  # The page size must stay constant across pages: Langfuse paginates by
  # page*limit, so shrinking `limit` on the last page re-reads earlier records.
  per="$want"; [ "$per" -gt 100 ] && per=100
  acc="$(mktemp)"
  while [ "$got" -lt "$want" ]; do
    body="$(lf_api "${path}${sep}page=${page}&limit=${per}")"
    jq -c '.data // []' <<<"$body" >>"$acc"
    n="$(jq -r '(.data // []) | length' <<<"$body")"
    [ "$n" = "0" ] && break
    got=$(( got + n ))
    pages="$(jq -r '.meta.totalPages // 1' <<<"$body")"
    [ "$page" -ge "$pages" ] && break
    page=$(( page + 1 ))
  done
  jq -c -s --argjson want "$want" 'add // [] | .[0:$want]' "$acc"
  rm -f "$acc"
}

# Shared jq prelude: lftext flattens Langfuse's free-form input/output payloads
# (strings, message arrays, {content}/{text} wrappers) into readable text;
# lfclip truncates with a visible marker so agents know data was cut.
LF_JQ_PRELUDE='
def lftext:
  if . == null then ""
  elif type == "string" then .
  elif type == "number" or type == "boolean" then tostring
  elif type == "array" then [ .[] | lftext ] | map(select(. != "")) | join("\n")
  elif type == "object" then
    if (has("role") and has("content")) then "[\(.role)] " + (.content | lftext)
    elif has("content") then (.content | lftext)
    elif has("text") then (.text | lftext)
    elif has("output") then (.output | lftext)
    else tojson end
  else tojson end;
def lfclip($n):
  if $n > 0 and (length > $n) then .[0:$n] + "…[+\(length - $n) more chars]" else . end;
def lfline: gsub("\n"; " ") | gsub("[[:space:]]+"; " ");
'

# Guard: this file is a library; running it directly is a no-op.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'langfuse-lib.sh is a sourced library; use the langfuse-* commands.\n' >&2
  exit 0
fi
