#!/bin/sh

GEMINI_DIAG_FAILURE_PATTERN='(interactive_failed rc=[1-9][0-9]*|noninteractive_failed rc=[1-9][0-9]*|child_exit.*rc=[1-9][0-9]*|Segmentation fault|upstream_auto_retry_failed=1|upstream_auto_retry_detected|gemini exited unexpectedly)'

gemini_diag_newest_run=""
gemini_diag_last_failed=""

gemini_diag_find_runs() {
  runs_dir="$1"
  gemini_diag_newest_run=""
  gemini_diag_last_failed=""

  [ -d "$runs_dir" ] || return 0

  run_list="$(
    for f in "$runs_dir"/*.log; do
      [ -f "$f" ] || continue
      printf '%s\n' "$f"
    done | sort
  )"

  [ -n "$run_list" ] || return 0

  gemini_diag_newest_run="$(printf '%s\n' "$run_list" | tail -n 1)"

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -qE "$GEMINI_DIAG_FAILURE_PATTERN" "$f"; then
      gemini_diag_last_failed="$f"
    fi
  done <<EOF
$run_list
EOF
}
