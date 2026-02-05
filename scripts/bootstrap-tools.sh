#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOOLS_DIR="$ROOT_DIR/.tools"
BIN_DIR="$TOOLS_DIR/bin"

mkdir -p "$BIN_DIR"

require_cmd() {
  local cmd="$1"
  local hint="$2"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd not found. $hint" >&2
    exit 1
  fi
}

require_cmd curl "Install curl to download tools."
require_cmd python3 "Install python3 to parse release metadata."
require_cmd tar "Install tar to extract archives."

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$OS" in
  darwin|linux) ;;
  *)
    echo "Unsupported OS: $OS" >&2
    exit 1
    ;;
esac

case "$ARCH" in
  x86_64|amd64)
    ARCH_SHELLCHECK="x86_64"
    ARCH_SHFMT="amd64"
    ;;
  arm64|aarch64)
    ARCH_SHELLCHECK="aarch64"
    ARCH_SHFMT="arm64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

fetch_latest_asset_url() {
  local repo="$1"
  local pattern="$2"

  python3 - "$repo" "$pattern" <<'PY'
import json
import re
import sys
import urllib.request

repo, pattern = sys.argv[1], sys.argv[2]
url = f"https://api.github.com/repos/{repo}/releases/latest"

with urllib.request.urlopen(url) as response:
    data = json.load(response)

regex = re.compile(pattern)
for asset in data.get("assets", []):
    name = asset.get("name", "")
    if regex.fullmatch(name):
        print(asset.get("browser_download_url", ""))
        sys.exit(0)

sys.exit(1)
PY
}

fetch_latest_tarball_url() {
  local repo="$1"

  python3 - "$repo" <<'PY'
import json
import sys
import urllib.request

repo = sys.argv[1]
url = f"https://api.github.com/repos/{repo}/releases/latest"

with urllib.request.urlopen(url) as response:
    data = json.load(response)

tarball_url = data.get("tarball_url", "")
if tarball_url:
    print(tarball_url)
    sys.exit(0)

sys.exit(1)
PY
}

install_shellcheck() {
  local target="$BIN_DIR/shellcheck"
  if [[ -x "$target" ]]; then
    echo "shellcheck already installed"
    return
  fi

  local pattern="^shellcheck-v[0-9.]+\\.${OS}\\.${ARCH_SHELLCHECK}\\.tar\\.xz$"
  local url
  if ! url=$(fetch_latest_asset_url "koalaman/shellcheck" "$pattern"); then
    echo "Failed to find shellcheck release asset for ${OS}/${ARCH_SHELLCHECK}" >&2
    exit 1
  fi

  local tmp_dir
  tmp_dir=$(mktemp -d "$TOOLS_DIR/tmp.shellcheck.XXXXXX")
  trap 'rm -rf "$tmp_dir"; trap - RETURN' RETURN

  curl -fsSL "$url" -o "$tmp_dir/shellcheck.tar.xz"
  tar -xJf "$tmp_dir/shellcheck.tar.xz" -C "$tmp_dir"

  local extracted
  extracted=$(find "$tmp_dir" -maxdepth 2 -type f -name shellcheck | head -n 1)
  if [[ -z "$extracted" ]]; then
    echo "Failed to locate shellcheck binary" >&2
    exit 1
  fi

  install -m 0755 "$extracted" "$target"
  echo "Installed shellcheck"
}

install_shfmt() {
  local target="$BIN_DIR/shfmt"
  if [[ -x "$target" ]]; then
    echo "shfmt already installed"
    return
  fi

  local pattern="^shfmt_v[0-9.]+_${OS}_${ARCH_SHFMT}$"
  local url
  if ! url=$(fetch_latest_asset_url "mvdan/sh" "$pattern"); then
    echo "Failed to find shfmt release asset for ${OS}/${ARCH_SHFMT}" >&2
    exit 1
  fi

  curl -fsSL "$url" -o "$target"
  chmod +x "$target"
  echo "Installed shfmt"
}

install_bats() {
  local target="$BIN_DIR/bats"
  if [[ -x "$target" ]]; then
    echo "bats already installed"
    return
  fi

  local pattern="^bats-core-[0-9.]+\\.tar\\.gz$"
  local url
  if ! url=$(fetch_latest_asset_url "bats-core/bats-core" "$pattern"); then
    if ! url=$(fetch_latest_tarball_url "bats-core/bats-core"); then
      echo "Failed to find bats-core release asset" >&2
      exit 1
    fi
  fi

  local tmp_dir
  tmp_dir=$(mktemp -d "$TOOLS_DIR/tmp.bats.XXXXXX")
  trap 'rm -rf "$tmp_dir"; trap - RETURN' RETURN

  curl -fsSL "$url" -o "$tmp_dir/bats.tar.gz"
  tar -xzf "$tmp_dir/bats.tar.gz" -C "$tmp_dir"

  local extracted
  extracted=$(find "$tmp_dir" -maxdepth 1 -type d -name "bats-core-*" | head -n 1)
  if [[ -z "$extracted" ]]; then
    echo "Failed to locate bats-core directory" >&2
    exit 1
  fi

  rm -rf "$TOOLS_DIR/bats"
  mv "$extracted" "$TOOLS_DIR/bats"
  ln -sf "$TOOLS_DIR/bats/bin/bats" "$target"
  echo "Installed bats"
}

install_shellcheck
install_shfmt
install_bats

echo "All tools installed to $BIN_DIR"
