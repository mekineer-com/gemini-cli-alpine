#!/bin/sh
set -eu

PREFIX=${1:-$HOME/.local}
GEMINI_CLI_VERSION=${GEMINI_CLI_VERSION:-0.34.0}

npm_config_prefix="$PREFIX" npm install -g "@google/gemini-cli@$GEMINI_CLI_VERSION"
"$(dirname "$0")/reapply-alpine-patches.sh" "$PREFIX"

echo "installed Gemini CLI $GEMINI_CLI_VERSION to $PREFIX"
echo "ensure $PREFIX/bin is first in PATH"
