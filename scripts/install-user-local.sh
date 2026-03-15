#!/bin/sh
set -eu

PREFIX=${1:-$HOME/.local}

npm_config_prefix="$PREFIX" npm install -g @google/gemini-cli@0.32.1
"$(dirname "$0")/reapply-alpine-patches.sh" "$PREFIX"

echo "installed Gemini CLI to $PREFIX"
echo "ensure $PREFIX/bin is first in PATH"
