#!/usr/bin/env bash
# Exercises bin/langfuse-lib.sh's offline logic: env-map resolution (including
# the `@file` secret indirection), project presets, relative time windows, and
# the paging arithmetic. No network and no real credentials are involved.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
LIB="$ROOT/bin/langfuse-lib.sh"

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

fail_test() { printf 'not ok - %s\n' "$1" >&2; exit 1; }

assert_equals() {
  local actual="$1" expected="$2" message="$3"
  [ "$actual" = "$expected" ] \
    || fail_test "$message: expected '$expected', got '$actual'"
}

assert_contains() {
  local output="$1" expected="$2" message="$3"
  case "$output" in
    *"$expected"*) ;;
    *) fail_test "$message: missing '$expected'" ;;
  esac
}

command -v jq >/dev/null 2>&1 || fail_test "jq is required"

WORK="$(mktemp -d)"
export LANGFUSE_ENVS="$WORK/envs.tsv"
export LANGFUSE_PROJECTS="$WORK/projects.tsv"

cat >"$WORK/secrets.json" <<'EOF'
{
  "LANGFUSE_BASE_URL": "https://fuse.example.test",
  "LANGFUSE_PUBLIC_KEY": "pk-lf-from-json",
  "LANGFUSE_SECRET_KEY": "sk-lf-from-json"
}
EOF

cat >"$WORK/secrets.env" <<'EOF'
# a comment line
export LANGFUSE_PUBLIC_KEY="pk-lf-from-dotenv"
LANGFUSE_SECRET_KEY='sk-lf-from-dotenv'
LANGFUSE_BASE_URL=https://dotenv.example.test
EOF

printf '# comment\n' >"$LANGFUSE_ENVS"
printf 'inline\thttps://inline.example.test/\tpk-inline\tsk-inline\n' >>"$LANGFUSE_ENVS"
printf 'fromjson\t-\t@%s\n' "$WORK/secrets.json" >>"$LANGFUSE_ENVS"
printf 'fromenvfile\thttps://override.example.test\t@%s\n' "$WORK/secrets.env" >>"$LANGFUSE_ENVS"

printf 'medulla\t^medulla-\n' >"$LANGFUSE_PROJECTS"
printf 'oh\t^(agent\\.turn|flow\\.run)\n' >>"$LANGFUSE_PROJECTS"

# shellcheck source=bin/langfuse-lib.sh
source "$LIB"

# --- env map ---------------------------------------------------------------

assert_equals "$(lf_env_aliases | paste -sd, -)" "inline,fromjson,fromenvfile" \
  "every non-comment alias is listed"

lf_config inline "" "" ""
assert_equals "$LF_BASE" "https://inline.example.test" "trailing slash is trimmed"
assert_equals "$LF_PK" "pk-inline" "inline public key"
assert_equals "$LF_SK" "sk-inline" "inline secret key"
assert_equals "$LF_ENV_R" "inline" "resolved alias is reported"

# `-` for base-url means "take it from the secret file too".
lf_config fromjson "" "" ""
assert_equals "$LF_BASE" "https://fuse.example.test" "base url read from JSON"
assert_equals "$LF_PK" "pk-lf-from-json" "public key read from JSON"
assert_equals "$LF_SK" "sk-lf-from-json" "secret key read from JSON"

# An explicit base-url column wins over the secret file's own value.
lf_config fromenvfile "" "" ""
assert_equals "$LF_BASE" "https://override.example.test" "column base url wins"
assert_equals "$LF_PK" "pk-lf-from-dotenv" "public key read from dotenv"
assert_equals "$LF_SK" "sk-lf-from-dotenv" "secret key read from dotenv (quotes stripped)"

# Flags outrank the map.
lf_config inline "https://flag.example.test" "pk-flag" "sk-flag"
assert_equals "$LF_BASE" "https://flag.example.test" "--base-url wins"
assert_equals "$LF_PK" "pk-flag" "--public-key wins"

# Environment variables are used when no alias is given.
(
  export LANGFUSE_PUBLIC_KEY=pk-env LANGFUSE_SECRET_KEY=sk-env \
         LANGFUSE_BASE_URL=https://env.example.test
  lf_config "" "" "" ""
  assert_equals "$LF_PK" "pk-env" "env credentials are used"
  assert_equals "$LF_ENV_R" "(env)" "env source is labelled"
)

# LANGFUSE_ENV names an alias.
(
  export LANGFUSE_ENV=fromjson
  lf_config "" "" "" ""
  assert_equals "$LF_PK" "pk-lf-from-json" "LANGFUSE_ENV selects an alias"
)

OUT="$( (lf_config nosuch "" "" "") 2>&1 || true )"
assert_contains "$OUT" "unknown Langfuse env 'nosuch'" "unknown alias fails loudly"
assert_contains "$OUT" "inline,fromjson,fromenvfile" "the error lists what is configured"

OUT="$( (lf_config "" "" "pk-only" "") 2>&1 || true )"
assert_contains "$OUT" "must be given together" "a half key pair is rejected"

# With no alias, no env vars and no `default` entry, a single-entry map is used
# but a multi-entry map must not guess.
OUT="$( (env -u LANGFUSE_ENV -u LANGFUSE_PUBLIC_KEY -u LANGFUSE_SECRET_KEY \
         bash -c 'source "$1"; lf_config "" "" "" ""' _ "$LIB") 2>&1 || true )"
assert_contains "$OUT" "no Langfuse env resolved" "an ambiguous map is not guessed at"

# --- project presets -------------------------------------------------------

assert_equals "$(lf_project_pattern medulla)" '^medulla-' "mapped preset"
assert_equals "$(lf_project_pattern oh)" '^(agent\.turn|flow\.run)' \
  "regex metacharacters survive the map"
assert_equals "$(lf_project_pattern unmapped)" 'unmapped' \
  "an unmapped alias is used as the pattern"
assert_equals "$(lf_project_pattern '')" '' "no project means no filter"

# --- time windows ----------------------------------------------------------

for spec in 30m 6h 7d 2w; do
  ISO="$(lf_iso "$spec")"
  case "$ISO" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*Z) ;;
    *) fail_test "lf_iso $spec did not produce an ISO timestamp: '$ISO'" ;;
  esac
done
assert_equals "$(lf_iso 2026-01-02T03:04:05Z)" "2026-01-02T03:04:05Z" \
  "an explicit timestamp passes through"
NOW="$(date -u +%s)"; THEN="$(lf_iso 1d)"
case "$(uname -s)" in
  Darwin) THEN_S="$(date -u -j -f %Y-%m-%dT%H:%M:%SZ "$THEN" +%s)" ;;
  *)      THEN_S="$(date -u -d "$THEN" +%s)" ;;
esac
DELTA=$(( NOW - THEN_S ))
[ "$DELTA" -gt 86000 ] && [ "$DELTA" -lt 87000 ] \
  || fail_test "lf_iso 1d is $DELTA seconds ago, expected ~86400"

# --- paging ----------------------------------------------------------------

# Stub lf_api with a fake 250-record endpoint to prove pages neither overlap
# nor drop records: Langfuse pages by page*limit, so the page size has to stay
# constant across requests.
lf_api() {
  local page limit
  page="$(sed -E 's/.*[?&]page=([0-9]+).*/\1/' <<<"$1")"
  limit="$(sed -E 's/.*[?&]limit=([0-9]+).*/\1/' <<<"$1")"
  jq -n --argjson page "$page" --argjson limit "$limit" --argjson total 250 '
    (($page - 1) * $limit) as $off
    | {data: [ range($off; ([$off + $limit, $total] | min)) | {id: .} ],
       meta: {page: $page, limit: $limit, totalItems: $total,
              totalPages: (($total / $limit) | ceil)}}'
}

for want in 1 100 150 250 400; do
  GOT="$(lf_api_paged "/traces?name=x" "$want")"
  EXPECT=$(( want > 250 ? 250 : want ))
  assert_equals "$(jq 'length' <<<"$GOT")" "$EXPECT" "paging returns $EXPECT of $want"
  assert_equals "$(jq '[.[].id] | unique | length' <<<"$GOT")" "$EXPECT" \
    "paging returns no duplicates at limit $want"
  assert_equals "$(jq '[.[].id] == ([.[].id] | sort)' <<<"$GOT")" "true" \
    "paging preserves order at limit $want"
done

printf 'ok - langfuse-lib config, presets, time windows, and paging\n'
