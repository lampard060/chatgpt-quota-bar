#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
VERSION=${1:-1.0.0}
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_NAME="ChatGPT-Quota-Bar-v$VERSION"
PACKAGE_DIR="$DIST_DIR/$PACKAGE_NAME"

"$ROOT_DIR/scripts/build.sh"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

ditto "$ROOT_DIR/build/ChatGPT 额度.app" "$PACKAGE_DIR/ChatGPT 额度.app"
cp "$ROOT_DIR/scripts/install-release.command" "$PACKAGE_DIR/安装.command"
cp "$ROOT_DIR/scripts/uninstall.command" "$PACKAGE_DIR/卸载.command"
cp "$ROOT_DIR/RELEASE_README.txt" "$PACKAGE_DIR/使用说明.txt"
chmod +x "$PACKAGE_DIR/安装.command" "$PACKAGE_DIR/卸载.command"

rm -f "$DIST_DIR/$PACKAGE_NAME.zip"
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$DIST_DIR/$PACKAGE_NAME.zip"
shasum -a 256 "$DIST_DIR/$PACKAGE_NAME.zip" > "$DIST_DIR/$PACKAGE_NAME.zip.sha256"

echo "$DIST_DIR/$PACKAGE_NAME.zip"
