#!/bin/sh
set -eu

GEMINI_BIN="${GEMINI_BIN:-$HOME/.local/bin/gemini}"
DIAG_LAST_BIN="${DIAG_LAST_BIN:-$HOME/.local/bin/gemini-diag-last}"
DIAG_BUNDLE_BIN="${DIAG_BUNDLE_BIN:-$HOME/.local/bin/gemini-diag-bundle}"
MODEL_OK="${MODEL_OK:-gemini-2.5-flash-lite}"
MODEL_FAIL="${MODEL_FAIL:-definitely-not-a-real-model}"
OUT_DIR="${OUT_DIR:-$HOME/.gemini/diagnostics/smoke}"
TS="$(date '+%Y%m%dT%H%M%S')"
TRANSCRIPT="$OUT_DIR/interactive-badflag-$TS.typescript"

mkdir -p "$OUT_DIR"

run_expect_success() {
  label="$1"
  shift
  echo "[smoke] $label"
  "$@"
}

run_expect_failure() {
  label="$1"
  shift
  echo "[smoke] $label (expecting non-zero)"
  set +e
  "$@"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "[smoke] FAIL: expected non-zero exit for: $label" >&2
    exit 1
  fi
  echo "[smoke] observed expected non-zero exit: rc=$rc"
}

run_expect_success "version" "$GEMINI_BIN" --version
run_expect_success "headless small prompt" "$GEMINI_BIN" -m "$MODEL_OK" -p "Reply with exactly: ok" --output-format text
run_expect_failure "headless api error" "$GEMINI_BIN" -m "$MODEL_FAIL" -p "hi" --output-format text
run_expect_failure "interactive badflag via PTY" script -qec "$GEMINI_BIN --badflag" "$TRANSCRIPT"

echo "[smoke] latest failing run"
"$DIAG_LAST_BIN"
echo "[smoke] creating bundle from latest failing run"
"$DIAG_BUNDLE_BIN"
echo "[smoke] transcript: $TRANSCRIPT"
