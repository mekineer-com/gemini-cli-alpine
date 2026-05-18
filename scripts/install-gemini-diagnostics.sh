#!/bin/sh
set -eu

PREFIX=${1:-$HOME/.local}
BINDIR="$PREFIX/bin"
WRAPPER="$BINDIR/gemini"
WRAPPER_ORIG="$BINDIR/gemini.orig"
DIAG_TOOL="$BINDIR/gemini-diag-last"
DIAG_BUNDLE_TOOL="$BINDIR/gemini-diag-bundle"
DIAG_COMMON_TOOL="$BINDIR/gemini-diag-common.sh"
TARGET_BUNDLE_REL="../lib/node_modules/@google/gemini-cli/bundle/gemini.js"
TARGET_DIST_REL="../lib/node_modules/@google/gemini-cli/dist/index.js"
TARGET_BUNDLE_ABS="$PREFIX/lib/node_modules/@google/gemini-cli/bundle/gemini.js"
TARGET_DIST_ABS="$PREFIX/lib/node_modules/@google/gemini-cli/dist/index.js"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/diagnostics"
WRAPPER_SRC="$SRC_DIR/gemini-wrapper.sh"
DIAG_TOOL_SRC="$SRC_DIR/gemini-diag-last.sh"
DIAG_BUNDLE_TOOL_SRC="$SRC_DIR/gemini-diag-bundle.sh"
DIAG_COMMON_SRC="$SRC_DIR/gemini-diag-common.sh"

for f in "$WRAPPER_SRC" "$DIAG_TOOL_SRC" "$DIAG_BUNDLE_TOOL_SRC" "$DIAG_COMMON_SRC"; do
  if [ ! -f "$f" ]; then
    echo "missing diagnostics source script: $f" >&2
    exit 1
  fi
done

[ -d "$BINDIR" ] || mkdir -p "$BINDIR"
if [ -L "$WRAPPER" ] && [ ! -e "$WRAPPER_ORIG" ]; then
  mv "$WRAPPER" "$WRAPPER_ORIG"
fi
if [ -L "$WRAPPER_ORIG" ] && [ ! -e "$WRAPPER_ORIG" ]; then
  rm -f "$WRAPPER_ORIG"
fi
if [ ! -e "$WRAPPER_ORIG" ]; then
  if [ -f "$TARGET_BUNDLE_ABS" ]; then
    ln -s "$TARGET_BUNDLE_REL" "$WRAPPER_ORIG"
  elif [ -f "$TARGET_DIST_ABS" ]; then
    ln -s "$TARGET_DIST_REL" "$WRAPPER_ORIG"
  else
    echo "missing gemini entrypoint under $PREFIX (checked bundle and dist paths)" >&2
    exit 1
  fi
fi

cp -f "$WRAPPER_SRC" "$WRAPPER"
cp -f "$DIAG_TOOL_SRC" "$DIAG_TOOL"
cp -f "$DIAG_BUNDLE_TOOL_SRC" "$DIAG_BUNDLE_TOOL"
cp -f "$DIAG_COMMON_SRC" "$DIAG_COMMON_TOOL"
chmod +x "$WRAPPER" "$DIAG_TOOL" "$DIAG_BUNDLE_TOOL" "$DIAG_COMMON_TOOL"

echo "installed diagnostics wrapper under $BINDIR (core mode)"
echo "optional extras: set GEMINI_DIAG_ENABLE_RSS=1 to enable RSS sampling for non-interactive runs"
