#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/open-code-review-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

fake_prefix="$TEST_ROOT/npm-prefix"
fake_bin="$TEST_ROOT/bin"
mkdir -p "$fake_prefix/bin" "$fake_bin"

cat > "$fake_bin/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "prefix" ]; then
  printf '%s\n' "$FAKE_NPM_PREFIX"
else
  printf '%s\n' "$*" >> "$FAKE_NPM_LOG"
fi
EOF

cat > "$fake_prefix/bin/ocr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s\n' "$*"
printf 'openai_key=%s\n' "${OPENAI_API_KEY:-}"
printf 'openrouter_key=%s\n' "${OPENROUTER_API_KEY:-}"
EOF

chmod +x "$fake_bin/npm" "$fake_prefix/bin/ocr"

output="$(
  PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_NPM_PREFIX="$fake_prefix" \
    OPENROUTER_API_KEY="test-openrouter-key" \
    "$ROOT/bin/ocr" review --from main --to feature
)"
case "$output" in
  *"args=review --from main --to feature"*) ;;
  *) echo "not ok - wrapper did not preserve arguments" >&2; exit 1 ;;
esac
case "$output" in
  *"openai_key=test-openrouter-key"*) ;;
  *) echo "not ok - wrapper did not map the OpenRouter key" >&2; exit 1 ;;
esac

zsh_output="$(
  PATH="$fake_bin:$ROOT/bin:/usr/bin:/bin" \
    FAKE_NPM_PREFIX="$fake_prefix" \
    OCR_REAL_BIN="$fake_prefix/bin/ocr" \
    OPENROUTER_API_KEY="test-openrouter-key" \
    zsh -c "source '$ROOT/zshrc'; ocr scan --path internal/agent"
)"
case "$zsh_output" in
  *"args=scan --path internal/agent"*) ;;
  *) echo "not ok - zsh function did not select the workspace wrapper" >&2; exit 1 ;;
esac

set +e
missing_key_output="$(
  PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_NPM_PREFIX="$fake_prefix" \
    OPENROUTER_API_KEY="" \
    "$ROOT/bin/ocr" review 2>&1
)"
missing_key_status=$?
set -e
[ "$missing_key_status" -eq 1 ] || {
  echo "not ok - missing key should fail" >&2
  exit 1
}
case "$missing_key_output" in
  *"OPENROUTER_API_KEY is not set"*) ;;
  *) echo "not ok - missing key error is unclear" >&2; exit 1 ;;
esac

dry_run_output="$("$ROOT/bin/install-open-code-review" --dry-run)"
case "$dry_run_output" in
  *"npm install --global @alibaba-group/open-code-review"*) ;;
  *) echo "not ok - installer dry run omitted npm action" >&2; exit 1 ;;
esac

echo "ok - OpenCodeReview wrapper and installer"
