#!/bin/sh

DIAG_ROOT="${GEMINI_DIAG_ROOT:-$HOME/.gemini/diagnostics}"
LATEST_LINK="$DIAG_ROOT/latest.log"
RUNS_DIR="$DIAG_ROOT/runs"
REPORT_DIR="$DIAG_ROOT/reports"
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
COMMON="$SELF_DIR/gemini-diag-common.sh"

if [ ! -f "$COMMON" ]; then
  echo "missing helper script: $COMMON" >&2
  exit 1
fi

. "$COMMON"
gemini_diag_find_runs "$RUNS_DIR"
newest_run="$gemini_diag_newest_run"
last_failed="$gemini_diag_last_failed"

echo "Diagnostics root: $DIAG_ROOT"
latest_target=""

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
  echo "Selected run file: $selected_run"
  echo "--- tail selected run ---"
  tail -n 120 "$selected_run" 2>/dev/null || echo "(unable to read selected run)"
  artifact_dir="$selected_run.artifacts"
  if [ -d "$artifact_dir" ]; then
    echo "--- artifacts for selected run ---"
    ls -lt "$artifact_dir" 2>/dev/null | sed -n '1,40p' || echo "(unable to list artifacts)"
  fi
else
  echo "No run logs found under $RUNS_DIR"
fi

echo "--- recent node diagnostic reports ---"
ls -lt "$REPORT_DIR" 2>/dev/null | sed -n '1,20p' || echo "(no report directory)"
