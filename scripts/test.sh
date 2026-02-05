#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOOLS_BIN="$ROOT_DIR/.tools/bin"

if [[ -d "$TOOLS_BIN" ]]; then
  export PATH="$TOOLS_BIN:$PATH"
fi

require_cmd() {
  local cmd="$1"
  local hint="$2"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd not found. $hint" >&2
    exit 1
  fi
}

require_cmd bats "Run scripts/bootstrap-tools.sh or install bats via your package manager."

bats "$ROOT_DIR/tests"
