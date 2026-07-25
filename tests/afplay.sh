#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMMAND="$ROOT/bin/afplay"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/afplay-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail_test() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

test_delegates_to_native_player() {
  local fake_player="$TEST_ROOT/native-player"
  local arguments="$TEST_ROOT/arguments"
  cat >"$fake_player" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$@" >"$arguments"
EOF
  chmod +x "$fake_player"

  AFPLAY_NATIVE="$fake_player" "$COMMAND" --volume 0.5 "sound file.aiff"

  [ "$(sed -n '1p' "$arguments")" = "--volume" ] \
    || fail_test "native option was not preserved"
  [ "$(sed -n '2p' "$arguments")" = "0.5" ] \
    || fail_test "native option value was not preserved"
  [ "$(sed -n '3p' "$arguments")" = "sound file.aiff" ] \
    || fail_test "native sound path was not preserved"
}

test_emits_one_fallback_bell() {
  local output
  output="$(
    AFPLAY_NATIVE="$TEST_ROOT/missing" AFPLAY_OUTPUT=stdout \
      "$COMMAND" /System/Library/Sounds/Glass.aiff |
      od -An -tu1 | tr -d '[:space:]'
  )"
  [ "$output" = "7" ] || fail_test "fallback did not emit exactly one BEL"
}

test_does_not_evaluate_arguments() {
  local marker="$TEST_ROOT/should-not-exist"
  AFPLAY_NATIVE="$TEST_ROOT/missing" AFPLAY_OUTPUT=silent \
    "$COMMAND" "\$(touch $marker)"
  [ ! -e "$marker" ] || fail_test "fallback evaluated a sound argument"
}

test_rejects_unknown_output_mode() {
  if AFPLAY_NATIVE="$TEST_ROOT/missing" AFPLAY_OUTPUT=network \
    "$COMMAND" >/dev/null 2>&1
  then
    fail_test "unknown output mode was accepted"
  fi
}

test_delegates_to_native_player
printf 'ok 1 - delegates arguments to the native player\n'
test_emits_one_fallback_bell
printf 'ok 2 - emits one terminal bell when native playback is absent\n'
test_does_not_evaluate_arguments
printf 'ok 3 - never evaluates fallback sound arguments\n'
test_rejects_unknown_output_mode
printf 'ok 4 - rejects unknown output modes\n'
printf '1..4\n'
