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
HISTORY="$OUT_DIR/history.tsv"

mkdir -p "$OUT_DIR"
start_epoch="$(date +%s)"

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
bundle_output="$("$DIAG_BUNDLE_BIN")"
echo "$bundle_output"
echo "[smoke] transcript: $TRANSCRIPT"

selected_run="$(printf '%s\n' "$bundle_output" | sed -n 's/^selected run: //p' | tail -n 1)"
bundle_tar="$(printf '%s\n' "$bundle_output" | sed -n 's/^bundle tar : //p' | tail -n 1)"
gemini_version="$("$GEMINI_BIN" --version 2>/dev/null | tr -d '\r' | tail -n 1 || echo unknown)"
end_epoch="$(date +%s)"
total_sec=$((end_epoch - start_epoch))
last_exit_line=""
last_exit_rc="unknown"
last_exit_dur="unknown"
error_class="(none)"
if [ -n "$selected_run" ] && [ -f "$selected_run" ]; then
  last_exit_line="$(grep -E '(interactive_exit|noninteractive_exit) rc=' "$selected_run" 2>/dev/null | tail -n 1 || true)"
  last_exit_rc="$(printf '%s\n' "$last_exit_line" | sed -n 's/.* rc=\([0-9][0-9]*\).*/\1/p' | head -n 1 || true)"
  if [ -z "$last_exit_rc" ]; then
    last_exit_rc="unknown"
  fi
  last_exit_dur="$(printf '%s\n' "$last_exit_line" | sed -n 's/.* dur=\([0-9][0-9]*s\).*/\1/p' | head -n 1 || true)"
  if [ -z "$last_exit_dur" ]; then
    last_exit_dur="unknown"
  fi
  error_class="$(grep -oE '[A-Za-z][A-Za-z0-9]+Error' "$selected_run" 2>/dev/null | head -n 1 || true)"
  if [ -z "$error_class" ]; then
    error_class="(none)"
  fi
fi

if [ ! -f "$HISTORY" ]; then
  printf 'ts\tgemini_version\tmodel_ok\tmodel_fail\ttotal_sec\tselected_run_rc\tselected_run_dur\terror_class\tbundle_tar\n' > "$HISTORY"
fi
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$TS" "$gemini_version" "$MODEL_OK" "$MODEL_FAIL" "$total_sec" "$last_exit_rc" "$last_exit_dur" "$error_class" "$bundle_tar" >> "$HISTORY"
echo "[smoke] history: $HISTORY"
