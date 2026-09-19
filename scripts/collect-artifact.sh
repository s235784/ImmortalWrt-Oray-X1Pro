#!/usr/bin/env bash
# Archive a finished X1 Pro sysupgrade image with reproducibility metadata.
#
# Usage: scripts/collect-artifact.sh /absolute/path/to/immortalwrt [profile]
# Example: scripts/collect-artifact.sh /absolute/path/to/immortalwrt daily

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 /absolute/path/to/immortalwrt [profile]" >&2
  exit 2
fi

OPENWRT_DIR=$1
PROFILE=${2:-daily}
REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
CONFIG_FILE="$REPO_DIR/config/x1pro-$PROFILE.config"

if ! git -C "$OPENWRT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not an ImmortalWrt Git worktree: $OPENWRT_DIR" >&2
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Configuration profile not found: $CONFIG_FILE" >&2
  exit 1
fi

mapfile -t IMAGES < <(find "$OPENWRT_DIR/bin/targets/mediatek/filogic" -maxdepth 1 \
  -type f -name '*oray_x1pro*sysupgrade.bin' -print)
if [ "${#IMAGES[@]}" -ne 1 ]; then
  echo "Expected exactly one X1 Pro sysupgrade image; found ${#IMAGES[@]}." >&2
  printf '%s\n' "${IMAGES[@]}" >&2
  exit 1
fi

IMAGE=${IMAGES[0]}
CONTROL=$(tar -xOf "$IMAGE" sysupgrade-oray_x1pro/CONTROL 2>/dev/null || true)
if ! printf '%s\n' "$CONTROL" | grep -Fqx 'BOARD=oray_x1pro'; then
  echo "Image metadata does not identify BOARD=oray_x1pro: $IMAGE" >&2
  exit 1
fi

SOURCE_TAG=$(git -C "$OPENWRT_DIR" describe --exact-match --tags 2>/dev/null || echo untagged)
SOURCE_COMMIT=$(git -C "$OPENWRT_DIR" rev-parse HEAD)
SOURCE_SHORT=$(git -C "$OPENWRT_DIR" rev-parse --short=12 HEAD)
BUILD_TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
BUILD_TIME=$(date +%Y%m%d-%H%M%S)
SAFE_TAG=$(printf '%s' "$SOURCE_TAG" | tr -c 'A-Za-z0-9._-' '_')
SAFE_PROFILE=$(printf '%s' "$PROFILE" | tr -c 'A-Za-z0-9._-' '_')
VERSION=${SAFE_TAG#v}
ARCHIVE_DIR="$REPO_DIR/output/${BUILD_TIME}_${VERSION}_${SOURCE_SHORT}_${SAFE_PROFILE}"

git_revision() {
  git -C "$1" rev-parse HEAD 2>/dev/null || printf 'not-a-git-worktree'
}

git_state() {
  if ! git -C "$1" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'not-a-git-worktree'
  elif [ -z "$(git -C "$1" status --porcelain)" ]; then
    printf 'clean'
  else
    printf 'dirty'
  fi
}

if [ -e "$ARCHIVE_DIR" ]; then
  echo "Refusing to overwrite existing archive directory: $ARCHIVE_DIR" >&2
  exit 1
fi
mkdir -p "$ARCHIVE_DIR"
IMAGE_MD5=$(md5sum "$IMAGE" | awk '{print $1}')
FIRMWARE_NAME="immortalwrt-${VERSION}-oray_x1pro-sysupgrade-md5_${IMAGE_MD5}.bin"
install -m 0644 "$IMAGE" "$ARCHIVE_DIR/$FIRMWARE_NAME"
install -m 0644 "$CONFIG_FILE" "$ARCHIVE_DIR/x1pro-$SAFE_PROFILE.config"
"$OPENWRT_DIR/scripts/diffconfig.sh" > "$ARCHIVE_DIR/x1pro-$SAFE_PROFILE.generated.config"

(
  cd "$ARCHIVE_DIR"
  md5sum "$FIRMWARE_NAME" > md5sums
  sha256sum "$FIRMWARE_NAME" > sha256sums
)

{
  printf 'image=%s\n' "$FIRMWARE_NAME"
  printf 'image_md5=%s\n' "$(awk '{print $1}' "$ARCHIVE_DIR/md5sums")"
  printf 'image_sha256=%s\n' "$(awk '{print $1}' "$ARCHIVE_DIR/sha256sums")"
  printf 'image_size_bytes=%s\n' "$(stat -c '%s' "$ARCHIVE_DIR/$FIRMWARE_NAME")"
  printf 'board=oray_x1pro\n'
  printf 'build_timestamp=%s\n' "$BUILD_TIMESTAMP"
  printf 'source_tag=%s\n' "$SOURCE_TAG"
  printf 'source_commit=%s\n' "$SOURCE_COMMIT"
  printf 'source_tree=%s\n' "$(git_state "$OPENWRT_DIR")"
  printf 'config_profile=%s\n' "$PROFILE"
  printf 'config_repo_commit=%s\n' "$(git_revision "$REPO_DIR")"
  printf 'config_repo_tree=%s\n' "$(git_state "$REPO_DIR")"
  printf 'argon_theme_commit=%s\n' "$(git_revision "$OPENWRT_DIR/package/luci-theme-argon")"
  printf 'argon_config_commit=%s\n' "$(git_revision "$OPENWRT_DIR/package/luci-app-argon-config")"
} > "$ARCHIVE_DIR/build-info.txt"

printf 'Archived firmware: %s\n' "$ARCHIVE_DIR/$FIRMWARE_NAME"
printf 'Metadata: %s\n' "$ARCHIVE_DIR/build-info.txt"
