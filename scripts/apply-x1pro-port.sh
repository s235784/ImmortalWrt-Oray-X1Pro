#!/usr/bin/env bash
# Apply the Oray X1 Pro port to a pinned ImmortalWrt source tree.
# Source: ../Action-Oray-X1Pro, origin/v25.12.

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /absolute/path/to/immortalwrt-source" >&2
  exit 2
fi

OPENWRT_DIR=$1
DTS_SOURCE="$ROOT_DIR/devices/mt7981b-oray-x1-pro.dts"
DTS_TARGET="$OPENWRT_DIR/target/linux/mediatek/dts/mt7981b-oray-x1-pro.dts"
PORT_PATCH="$ROOT_DIR/patches/0001-mediatek-filogic-add-oray-x1-pro.patch"

if ! git -C "$OPENWRT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not an ImmortalWrt Git worktree: $OPENWRT_DIR" >&2
  exit 1
fi

install -D -m 0644 "$DTS_SOURCE" "$DTS_TARGET"

if git -C "$OPENWRT_DIR" apply --reverse --check "$PORT_PATCH" 2>/dev/null; then
  echo "X1 Pro port is already applied."
else
  git -C "$OPENWRT_DIR" apply --check "$PORT_PATCH"
  git -C "$OPENWRT_DIR" apply "$PORT_PATCH"
  echo "Applied X1 Pro port."
fi

