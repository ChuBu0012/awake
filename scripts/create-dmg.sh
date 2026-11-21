#!/usr/bin/env bash
# scripts/create-dmg.sh
# Packages Awake.app into a clean, distributable macOS .dmg archive

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
APP_NAME="Awake"
BUNDLE_NAME="${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_OUTPUT="$BUILD_DIR/$DMG_NAME"
STAGING_DIR="/tmp/awake-dmg.$$"
MOUNT_DIR="/tmp/awake-mount.$$"

echo "==> Preparing to build $DMG_NAME..."

# 1. Ensure build exists
if [ ! -d "$BUILD_DIR/$BUNDLE_NAME" ]; then
    echo "==> $BUNDLE_NAME not found in $BUILD_DIR. Building first..."
    make -C "$REPO_ROOT" build
fi

# 2. Apply Ad-hoc code signature for modern macOS Gatekeeper compatibility
echo "==> Applying Ad-hoc code signature to $BUNDLE_NAME..."
codesign -s - --force --deep --options runtime "$BUILD_DIR/$BUNDLE_NAME"

# 3. Setup staging area
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$BUILD_DIR/$BUNDLE_NAME" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# 4. Create compressed UDZO disk image
echo "==> Creating compressed .dmg via hdiutil..."
rm -f "$DMG_OUTPUT"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"

rm -rf "$STAGING_DIR"

# 4. Verify disk image integrity
echo "==> Verifying generated $DMG_NAME..."
hdiutil verify "$DMG_OUTPUT"

# Test mount & structure
mkdir -p "$MOUNT_DIR"
hdiutil attach "$DMG_OUTPUT" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >/dev/null

if [ ! -d "$MOUNT_DIR/$BUNDLE_NAME" ] || [ ! -L "$MOUNT_DIR/Applications" ]; then
    echo "ERROR: DMG contents missing expected files." >&2
    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
    rm -rf "$MOUNT_DIR"
    exit 1
fi

hdiutil detach "$MOUNT_DIR" -force >/dev/null
rm -rf "$MOUNT_DIR"

echo "==> Successfully created distributable DMG: $DMG_OUTPUT"
ls -lh "$DMG_OUTPUT"
