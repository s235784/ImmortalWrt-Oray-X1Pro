#!/usr/bin/env bash
# Fetch the third-party Argon LuCI packages at tested, fixed revisions.
#
# Usage: scripts/prepare-argon-packages.sh /absolute/path/to/immortalwrt

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /absolute/path/to/immortalwrt" >&2
  exit 2
fi

OPENWRT_DIR=$1
if ! git -C "$OPENWRT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not an ImmortalWrt Git worktree: $OPENWRT_DIR" >&2
  exit 1
fi

ARGON_THEME_REPO=https://github.com/jerrykuku/luci-theme-argon.git
ARGON_THEME_COMMIT=2a28799ca063aba7edc3314143b93c8325c86df4
ARGON_CONFIG_REPO=https://github.com/jerrykuku/luci-app-argon-config.git
ARGON_CONFIG_COMMIT=3e099a37c3f71d0de677f1b6b0f4bffd57d91dac

prepare_package() {
  local name=$1
  local repo=$2
  local commit=$3
  local target="$OPENWRT_DIR/package/$name"

  if [ -e "$target" ] && ! git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Refusing to replace non-Git directory: $target" >&2
    exit 1
  fi

  if [ ! -e "$target" ]; then
    git clone --filter=blob:none "$repo" "$target"
  fi

  git -C "$target" fetch --tags origin
  git -C "$target" checkout --detach "$commit"

  if [ ! -f "$target/Makefile" ]; then
    echo "Argon package has no Makefile: $target" >&2
    exit 1
  fi

  echo "$name: $(git -C "$target" rev-parse HEAD)"
}

prepare_package luci-theme-argon "$ARGON_THEME_REPO" "$ARGON_THEME_COMMIT"
prepare_package luci-app-argon-config "$ARGON_CONFIG_REPO" "$ARGON_CONFIG_COMMIT"
