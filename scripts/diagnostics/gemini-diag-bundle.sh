#!/bin/sh
set -eu

DIAG_ROOT="${GEMINI_DIAG_ROOT:-$HOME/.gemini/diagnostics}"
RUNS_DIR="$DIAG_ROOT/runs"
REPORT_DIR="$DIAG_ROOT/reports"
LAUNCH_LOG="$DIAG_ROOT/launcher.log"
BUNDLES_DIR="$DIAG_ROOT/bundles"
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
COMMON="$SELF_DIR/gemini-diag-common.sh"

if [ ! -f "$COMMON" ]; then
  echo "missing helper script: $COMMON" >&2
  exit 1
fi

. "$COMMON"

mkdir -p "$BUNDLES_DIR"

selected_run=""
gemini_diag_find_runs "$RUNS_DIR"
newest_run="$gemini_diag_newest_run"
last_failed="$gemini_diag_last_failed"

if [ -n "$last_failed" ]; then
  selected_run="$last_failed"
elif [ -n "$newest_run" ]; then
  selected_run="$newest_run"
fi

if [ -z "$selected_run" ] || [ ! -f "$selected_run" ]; then
  echo "No run log found under $RUNS_DIR" >&2
  exit 1
fi

run_base=$(basename "$selected_run" .log)
bundle_id="$(date '+%Y%m%dT%H%M%S')-$run_base"
bundle_dir="$BUNDLES_DIR/$bundle_id"
mkdir -p "$bundle_dir"

cp -f "$selected_run" "$bundle_dir/"

artifact_dir="$RUNS_DIR/$run_base.artifacts"
if [ -d "$artifact_dir" ]; then
  cp -a "$artifact_dir" "$bundle_dir/"
fi

if [ -d "$REPORT_DIR" ]; then
  report_count=0
  for r in "$REPORT_DIR"/*; do
    [ -f "$r" ] || continue
    cp -f "$r" "$bundle_dir/" 2>/dev/null || true
    report_count=$((report_count + 1))
    if [ "$report_count" -ge 5 ]; then
      break
    fi
  done
fi

if [ -f "$LAUNCH_LOG" ]; then
  tail -n 400 "$LAUNCH_LOG" > "$bundle_dir/launcher.tail.log" 2>/dev/null || true
fi

tmp_ref_list="$bundle_dir/tmp_client_error_paths.txt"
grep -o '/tmp/gemini-client-error-[^ ]*\.json' "$selected_run" 2>/dev/null | sort -u > "$tmp_ref_list" || true
if [ -s "$tmp_ref_list" ]; then
  mkdir -p "$bundle_dir/tmp_reports"
  while IFS= read -r p; do
    if [ -f "$p" ]; then
      cp -f "$p" "$bundle_dir/tmp_reports/" 2>/dev/null || true
    fi
  done < "$tmp_ref_list"
fi

meta="$bundle_dir/metadata.txt"
model=""
model="$(sed -n 's/.* args=.*-m \([^ ]*\).*/\1/p' "$selected_run" | head -n 1 || true)"
if [ -z "$model" ]; then
  model="(default)"
fi
error_class="$(grep -oE '[A-Za-z][A-Za-z0-9]+Error' "$selected_run" 2>/dev/null | head -n 1 || true)"
if [ -z "$error_class" ]; then
  error_class="(none)"
fi
quota_context=0
if grep -qiE 'quota exceeded|capacity-related|resource exhausted|rate limit|too many requests|[^0-9]429[^0-9]' "$selected_run" 2>/dev/null; then
  quota_context=1
fi
last_exit_line="$(grep -E '(interactive_exit|noninteractive_exit) rc=' "$selected_run" 2>/dev/null | tail -n 1 || true)"
last_rc="$(printf '%s\n' "$last_exit_line" | sed -n 's/.* rc=\([0-9][0-9]*\).*/\1/p' | head -n 1 || true)"
if [ -z "$last_rc" ]; then
  last_rc="unknown"
fi
last_dur="$(printf '%s\n' "$last_exit_line" | sed -n 's/.* dur=\([0-9][0-9]*s\).*/\1/p' | head -n 1 || true)"
if [ -z "$last_dur" ]; then
  last_dur="unknown"
fi
{
  echo "created_at=$(date -Iseconds)"
  echo "selected_run=$selected_run"
  echo "run_base=$run_base"
  echo "model=$model"
  echo "error_class=$error_class"
  echo "quota_context=$quota_context"
  echo "last_exit_rc=$last_rc"
  echo "last_exit_dur=$last_dur"
  echo "hostname=$(hostname 2>/dev/null || echo unknown)"
  echo "uname=$(uname -a 2>/dev/null || echo unknown)"
  if command -v gemini >/dev/null 2>&1; then
    echo "gemini_version=$(gemini --version 2>/dev/null || echo unknown)"
  fi
} > "$meta"

tar_path="$bundle_dir.tar.gz"
tar -C "$BUNDLES_DIR" -czf "$tar_path" "$bundle_id"

echo "selected run: $selected_run"
echo "bundle dir : $bundle_dir"
echo "bundle tar : $tar_path"
