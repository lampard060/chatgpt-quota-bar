#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/ChatGPT 额度.app"
MODULE_CACHE="$BUILD_DIR/module-cache"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
  -swift-version 5 \
  -O \
  -framework AppKit \
  "$ROOT_DIR/Sources/ChatGPTQuotaBar/QuotaModels.swift" \
  "$ROOT_DIR/Sources/ChatGPTQuotaBar/QuotaRPCClient.swift" \
  "$ROOT_DIR/Sources/ChatGPTQuotaBar/main.swift" \
  -o "$APP_DIR/Contents/MacOS/ChatGPTQuotaBar"

cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"

echo "$APP_DIR"
