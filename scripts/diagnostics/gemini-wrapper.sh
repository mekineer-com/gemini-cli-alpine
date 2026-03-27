#!/bin/sh
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TARGET="$SELF_DIR/../lib/node_modules/@google/gemini-cli/dist/index.js"
NODE_BIN="${GEMINI_NODE_BIN:-$(command -v node 2>/dev/null || true)}"
DIAG_ROOT="${GEMINI_DIAG_ROOT:-$HOME/.gemini/diagnostics}"
RUNS_DIR="$DIAG_ROOT/runs"
REPORT_DIR="$DIAG_ROOT/reports"
LAUNCH_LOG="$DIAG_ROOT/launcher.log"
LATEST_LINK="$DIAG_ROOT/latest.log"
RUN_ARTIFACTS_DIR=""
SAMPLE_SEC="${GEMINI_DIAG_SAMPLE_SEC:-2}"
MAX_RSS_MB="${GEMINI_MAX_RSS_MB:-0}"
ENABLE_RSS="${GEMINI_DIAG_ENABLE_RSS:-0}"
DEBUG_DISABLE_RETRY="${GEMINI_DEBUG_DISABLE_RETRY:-0}"

if [ ! -f "$TARGET" ]; then
  echo "gemini wrapper: target missing: $TARGET" >&2
  exit 127
fi
if [ -z "$NODE_BIN" ] || [ ! -x "$NODE_BIN" ]; then
  echo "gemini wrapper: node binary not found (set GEMINI_NODE_BIN=/path/to/node)" >&2
  exit 127
fi

mkdir -p "$RUNS_DIR" "$REPORT_DIR" 2>/dev/null || true
RUN_ID="$(date '+%Y%m%dT%H%M%S')-$$"
RUN_LOG="$RUNS_DIR/$RUN_ID.log"
rm -f "$LATEST_LINK" 2>/dev/null || true
ln -s "$RUN_LOG" "$LATEST_LINK" 2>/dev/null || true

log_event() {
  line="$(date -Iseconds)\t$*"
  printf '%s\n' "$line" >> "$LAUNCH_LOG" 2>/dev/null || true
  printf '%s\n' "$line" >> "$RUN_LOG" 2>/dev/null || true
}

is_interactive=1
for arg in "$@"; do
  case "$arg" in
    -p|--prompt|--output-format|--version|-v|--help|-h)
      is_interactive=0
      ;;
  esac
done

export GEMINI_DIAG_FILE="$RUN_LOG"
export GEMINI_DIAG_REPORT_DIR="$REPORT_DIR"
if [ "$DEBUG_DISABLE_RETRY" = "1" ]; then
  export GEMINI_CLI_NO_RELAUNCH="true"
  export GEMINI_DISABLE_INTERACTIVE_AUTO_RETRY="1"
  export GEMINI_DISABLE_INTERACTIVE_AUTO_RECOVER="1"
fi
# Alpine + node-pty can segfault in long sessions; default to child_process unless overridden.
if [ -z "${GEMINI_PTY_INFO:-}" ] && [ -f /etc/alpine-release ] && [ "${GEMINI_FORCE_NODE_PTY:-0}" != "1" ]; then
  export GEMINI_PTY_INFO="child_process"
  pty_mode_note="child_process(alpine_default)"
else
  pty_mode_note="${GEMINI_PTY_INFO:-auto}"
fi

log_event "session_start pid=$$ ppid=$PPID cwd=$(pwd) tty_in=$([ -t 0 ] && echo 1 || echo 0) tty_out=$([ -t 1 ] && echo 1 || echo 0) pty_mode=$pty_mode_note args=$*"
if [ "$DEBUG_DISABLE_RETRY" = "1" ]; then
  log_event "debug_disable_retry=1 env_no_relaunch=1"
fi

with_stderr_tee_foreground() {
  err_pipe=$(mktemp "$RUNS_DIR/.stderr.${RUN_ID}.XXXXXX")
  rm -f "$err_pipe"
  mkfifo "$err_pipe"
  tee -a "$RUN_LOG" < "$err_pipe" >&2 &
  err_tee_pid=$!
  "$@" 2>"$err_pipe"
  rc=$?
  wait "$err_tee_pid" 2>/dev/null || true
  rm -f "$err_pipe"
  return "$rc"
}

start_stderr_tee_pipe() {
  err_pipe=$(mktemp "$RUNS_DIR/.stderr.${RUN_ID}.XXXXXX")
  rm -f "$err_pipe"
  mkfifo "$err_pipe"
  tee -a "$RUN_LOG" < "$err_pipe" >&2 &
  err_tee_pid=$!
}

stop_stderr_tee_pipe() {
  wait "$err_tee_pid" 2>/dev/null || true
  rm -f "$err_pipe"
}

print_crash_notice() {
  crash_code="$1"
  printf 'gemini exited unexpectedly (code %s). diagnostics: %s\n' "$crash_code" "$RUN_LOG" >&2
}

capture_client_error_jsons() {
  RUN_ARTIFACTS_DIR="$RUNS_DIR/$RUN_ID.artifacts"
  mkdir -p "$RUN_ARTIFACTS_DIR" 2>/dev/null || true
  copied=0
  refs="$(grep -o '/tmp/gemini-client-error-[^ ]*\.json' "$RUN_LOG" 2>/dev/null | sort -u || true)"
  if [ -n "$refs" ]; then
    for f in $refs; do
      if [ -f "$f" ]; then
        out="$RUN_ARTIFACTS_DIR/$(basename "$f")"
        cp -f "$f" "$out" 2>/dev/null || true
        log_event "artifact_copy type=client_error_json src=$f dst=$out"
        copied=1
      else
        log_event "artifact_copy type=client_error_json src=$f missing=1"
      fi
    done
  else
    log_event "artifact_copy type=client_error_json none_referenced_in_run_log=1"
  fi
  if [ "$copied" -eq 0 ]; then
    if [ -n "$refs" ]; then
      log_event "artifact_copy type=client_error_json referenced_but_unavailable=1"
    else
      log_event "artifact_copy type=client_error_json none_found=1"
    fi
  fi
}

record_upstream_retry_markers() {
  retry_detected=0
  if grep -q 'Gemini hit an unexpected error. Retrying interactive session once...' "$RUN_LOG"; then
    retry_detected=1
    log_event "upstream_auto_retry_detected source=index_entrypoint"
  fi
  if grep -q 'Retrying interactive session once...' "$RUN_LOG"; then
    retry_detected=1
    log_event "upstream_auto_retry_detected source=cli_runtime"
  fi
  if grep -q 'Automatic retry failed. Exiting.' "$RUN_LOG"; then
    log_event "upstream_auto_retry_failed=1"
  fi
}

run_cmd_foreground() {
  log_event "run_start mode=foreground node=$NODE_BIN target=$TARGET args=$*"
  with_stderr_tee_foreground \
    "$NODE_BIN" \
    --no-warnings=DEP0040 \
    --trace-uncaught \
    --trace-warnings \
    --unhandled-rejections=strict \
    --report-uncaught-exception \
    --report-on-fatalerror \
    --report-on-signal \
    --report-signal=SIGSEGV \
    --report-directory "$REPORT_DIR" \
    "$TARGET" "$@"
  rc=$?
  log_event "child_exit rc=$rc max_rss_kb=na max_rss_mb=na mode=foreground"
  return "$rc"
}

run_cmd_sampled() {
  log_event "run_start mode=sampled node=$NODE_BIN target=$TARGET args=$*"
  start_stderr_tee_pipe
  "$NODE_BIN" \
    --no-warnings=DEP0040 \
    --trace-uncaught \
    --trace-warnings \
    --unhandled-rejections=strict \
    --report-uncaught-exception \
    --report-on-fatalerror \
    --report-on-signal \
    --report-signal=SIGSEGV \
    --report-directory "$REPORT_DIR" \
    "$TARGET" "$@" 2>"$err_pipe" &
  child_pid=$!
  max_rss_kb=0
  cap_kb=0
  if [ "$MAX_RSS_MB" -gt 0 ] 2>/dev/null; then
    cap_kb=$((MAX_RSS_MB * 1024))
  fi
  log_event "child_spawn pid=$child_pid sample_sec=$SAMPLE_SEC max_rss_mb=$MAX_RSS_MB"
  while kill -0 "$child_pid" 2>/dev/null; do
    rss_kb=$(awk '/^VmRSS:/ {print $2}' "/proc/$child_pid/status" 2>/dev/null || true)
    if [ -n "$rss_kb" ] && [ "$rss_kb" -gt "$max_rss_kb" ] 2>/dev/null; then
      max_rss_kb=$rss_kb
      log_event "rss_peak pid=$child_pid rss_kb=$rss_kb rss_mb=$((rss_kb / 1024))"
      if [ "$cap_kb" -gt 0 ] && [ "$rss_kb" -gt "$cap_kb" ] 2>/dev/null; then
        log_event "rss_cap_exceeded pid=$child_pid rss_kb=$rss_kb cap_kb=$cap_kb sending=TERM"
        kill -TERM "$child_pid" 2>/dev/null || true
        sleep 1
        kill -KILL "$child_pid" 2>/dev/null || true
      fi
    fi
    sleep "$SAMPLE_SEC"
  done
  wait "$child_pid"
  rc=$?
  stop_stderr_tee_pipe
  log_event "child_exit pid=$child_pid rc=$rc max_rss_kb=$max_rss_kb max_rss_mb=$((max_rss_kb / 1024))"
  return "$rc"
}

if [ -t 0 ] && [ -t 1 ] && [ "$is_interactive" -eq 1 ]; then
  start_ts=$(date +%s)
  run_cmd_foreground "$@"
  rc=$?
  end_ts=$(date +%s)
  dur=$((end_ts - start_ts))
  log_event "interactive_exit rc=$rc dur=${dur}s args=$*"
  record_upstream_retry_markers

  if [ "$rc" -ne 0 ] || [ "$retry_detected" -eq 1 ]; then
    capture_client_error_jsons
  fi

  if [ "$rc" -ne 0 ] && [ "$rc" -ne 130 ]; then
    print_crash_notice "$rc"
    log_event "interactive_failed rc=$rc"
  fi
  exit "$rc"
fi

start_ts=$(date +%s)
if [ "$ENABLE_RSS" -eq 1 ] 2>/dev/null; then
  run_cmd_sampled "$@"
else
  run_cmd_foreground "$@"
fi
rc=$?
end_ts=$(date +%s)
dur=$((end_ts - start_ts))
log_event "noninteractive_exit rc=$rc dur=${dur}s args=$*"
if [ "$rc" -ne 0 ]; then
  capture_client_error_jsons
  log_event "noninteractive_failed rc=$rc"
fi
exit "$rc"
