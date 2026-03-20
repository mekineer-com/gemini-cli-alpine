#!/bin/sh
set -eu

PREFIX=${1:-$HOME/.local}
BINDIR="$PREFIX/bin"
WRAPPER="$BINDIR/gemini"
WRAPPER_ORIG="$BINDIR/gemini.orig"
DIAG_TOOL="$BINDIR/gemini-diag-last"

[ -d "$BINDIR" ] || mkdir -p "$BINDIR"
if [ -L "$WRAPPER" ] && [ ! -e "$WRAPPER_ORIG" ]; then
  mv "$WRAPPER" "$WRAPPER_ORIG"
fi
if [ ! -e "$WRAPPER_ORIG" ]; then
  ln -s ../lib/node_modules/@google/gemini-cli/dist/index.js "$WRAPPER_ORIG"
fi

cat > "$WRAPPER" <<'EOS'
#!/bin/sh
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TARGET="$SELF_DIR/../lib/node_modules/@google/gemini-cli/dist/index.js"
NODE_BIN="/usr/bin/node"
DIAG_ROOT="${GEMINI_DIAG_ROOT:-$HOME/.gemini/diagnostics}"
RUNS_DIR="$DIAG_ROOT/runs"
REPORT_DIR="$DIAG_ROOT/reports"
LAUNCH_LOG="$DIAG_ROOT/launcher.log"
LATEST_LINK="$DIAG_ROOT/latest.log"
SAMPLE_SEC="${GEMINI_DIAG_SAMPLE_SEC:-2}"
MAX_RSS_MB="${GEMINI_MAX_RSS_MB:-0}"
ENABLE_RSS="${GEMINI_DIAG_ENABLE_RSS:-0}"

if [ ! -f "$TARGET" ]; then
  echo "gemini wrapper: target missing: $TARGET" >&2
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

log_event "session_start pid=$$ ppid=$PPID cwd=$(pwd) tty_in=$([ -t 0 ] && echo 1 || echo 0) tty_out=$([ -t 1 ] && echo 1 || echo 0) args=$*"

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
  log_event "noninteractive_failed rc=$rc"
fi
exit "$rc"
EOS
chmod +x "$WRAPPER"

cat > "$DIAG_TOOL" <<'EOS'
#!/bin/sh
DIAG_ROOT="${GEMINI_DIAG_ROOT:-$HOME/.gemini/diagnostics}"
LATEST_LINK="$DIAG_ROOT/latest.log"
RUNS_DIR="$DIAG_ROOT/runs"
REPORT_DIR="$DIAG_ROOT/reports"

echo "Diagnostics root: $DIAG_ROOT"
latest_target=""
newest_run=""
last_failed=""
if [ -d "$RUNS_DIR" ]; then
  newest_run=$(ls -1t "$RUNS_DIR"/*.log 2>/dev/null | head -n 1 || true)
  for f in $(ls -1t "$RUNS_DIR"/*.log 2>/dev/null); do
    if grep -qE '(child_exit.*rc=[1-9][0-9]*|interactive_exit rc=[1-9][0-9]*|interactive_failed rc=[1-9][0-9]*|noninteractive_failed rc=[1-9][0-9]*)' "$f"; then
      last_failed="$f"
      break
    fi
  done
fi
if [ -L "$LATEST_LINK" ] || [ -f "$LATEST_LINK" ]; then
  latest_target=$(readlink "$LATEST_LINK" 2>/dev/null || true)
fi
if [ -n "$latest_target" ]; then
  echo "Latest symlink target: $latest_target"
fi
if [ -n "$newest_run" ]; then
  echo "Newest run file: $newest_run"
fi
if [ -n "$last_failed" ]; then
  selected_run="$last_failed"
  echo "Selected run: latest failing run"
elif [ -n "$latest_target" ] && [ -f "$latest_target" ]; then
  selected_run="$latest_target"
  echo "Selected run: latest symlink target"
else
  selected_run="$newest_run"
  echo "Selected run: newest run file"
fi
if [ -n "$selected_run" ] && [ -f "$selected_run" ]; then
  echo "--- tail selected run ---"
  tail -n 120 "$selected_run" 2>/dev/null || echo "(unable to read selected run)"
else
  echo "No run logs found under $RUNS_DIR"
fi

echo "--- recent node diagnostic reports ---"
ls -lt "$REPORT_DIR" 2>/dev/null | sed -n '1,20p' || echo "(no report directory)"
EOS
chmod +x "$DIAG_TOOL"

echo "installed diagnostics wrapper under $BINDIR (core mode)"
echo "optional extras: set GEMINI_DIAG_ENABLE_RSS=1 to enable RSS sampling for non-interactive runs"
