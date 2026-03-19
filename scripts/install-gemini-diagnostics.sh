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

if [ ! -f "$TARGET" ]; then
  echo "gemini wrapper: target missing: $TARGET" >&2
  exit 127
fi

mkdir -p "$RUNS_DIR" "$REPORT_DIR" 2>/dev/null || true
RUN_ID="$(date '+%Y%m%dT%H%M%S')-$$"
RUN_LOG="$RUNS_DIR/$RUN_ID.log"
ln -sfn "$RUN_LOG" "$LATEST_LINK" 2>/dev/null || true

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

run_cmd() {
  log_event "run_start node=$NODE_BIN target=$TARGET args=$*"
  "$NODE_BIN" \
    --no-warnings=DEP0040 \
    --trace-uncaught \
    --trace-warnings \
    --unhandled-rejections=strict \
    --report-uncaught-exception \
    --report-on-fatalerror \
    --report-directory "$REPORT_DIR" \
    "$TARGET" "$@"
}

if [ -t 0 ] && [ -t 1 ] && [ "$is_interactive" -eq 1 ]; then
  start_ts=$(date +%s)
  run_cmd "$@"
  rc=$?
  end_ts=$(date +%s)
  dur=$((end_ts - start_ts))
  log_event "interactive_exit rc=$rc dur=${dur}s args=$*"

  if [ "$rc" -ne 0 ] && [ "$rc" -ne 130 ]; then
    echo "gemini exited unexpectedly (code $rc). retrying once..." >&2
    log_event "interactive_retry_first rc=$rc"
    retry_start_ts=$(date +%s)
    run_cmd "$@"
    rc=$?
    retry_end_ts=$(date +%s)
    retry_dur=$((retry_end_ts - retry_start_ts))
    log_event "interactive_retry_exit rc=$rc dur=${retry_dur}s args=$*"
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 130 ]; then
      echo "gemini failed again (code $rc). diagnostics: $RUN_LOG" >&2
      log_event "interactive_retry_failed rc=$rc"
    else
      echo "gemini recovered after retry. diagnostics: $RUN_LOG" >&2
      log_event "interactive_retry_recovered rc=$rc"
    fi
  elif [ "$rc" -eq 0 ] && [ "$dur" -lt 5 ]; then
    echo "gemini ended quickly (code 0, ${dur}s). diagnostics: $RUN_LOG" >&2
    log_event "interactive_quick_exit rc=0 dur=${dur}s"
  fi
  exit "$rc"
fi

start_ts=$(date +%s)
run_cmd "$@"
rc=$?
end_ts=$(date +%s)
dur=$((end_ts - start_ts))
log_event "noninteractive_exit rc=$rc dur=${dur}s args=$*"
exit "$rc"
EOS
chmod +x "$WRAPPER"

cat > "$DIAG_TOOL" <<'EOS'
#!/bin/sh
DIAG_ROOT="${GEMINI_DIAG_ROOT:-$HOME/.gemini/diagnostics}"
LATEST_LINK="$DIAG_ROOT/latest.log"
REPORT_DIR="$DIAG_ROOT/reports"

echo "Diagnostics root: $DIAG_ROOT"
if [ -L "$LATEST_LINK" ] || [ -f "$LATEST_LINK" ]; then
  latest_target=$(readlink "$LATEST_LINK" 2>/dev/null || true)
  [ -n "$latest_target" ] && echo "Latest run log: $latest_target"
  echo "--- tail latest log ---"
  tail -n 120 "$LATEST_LINK" 2>/dev/null || echo "(unable to read latest log)"
else
  echo "No latest log found at $LATEST_LINK"
fi

echo "--- recent node diagnostic reports ---"
ls -lt "$REPORT_DIR" 2>/dev/null | sed -n '1,20p' || echo "(no report directory)"
EOS
chmod +x "$DIAG_TOOL"

echo "installed diagnostics wrapper under $BINDIR"
