#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$PROJECT_DIR/frontend/swift"
BUILD_DIR="$PROJECT_DIR/.build-local"
APP_DIR="$BUILD_DIR/VoiceForge.app"
SOURCES=("$SWIFT_DIR"/Sources/VoiceForgeMenu/*.swift)
FALLBACK_SOURCE="$PROJECT_DIR/frontend/native-fallback/main.m"

mkdir -p "$BUILD_DIR"
SDK_INTERFACE="$(xcrun --show-sdk-path)/System/Library/Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface"
COMPILER_BUILD="$(
  xcrun swiftc --version 2>&1 |
    grep -oE 'swiftlang-[^ ]+' |
    head -1 |
    cut -d- -f2
)"
SDK_BUILD="$(
  grep -oE 'swiftlang-[^ ]+' "$SDK_INTERFACE" |
    head -1 |
    cut -d- -f2
)"

if [[ -n "$COMPILER_BUILD" && "$COMPILER_BUILD" == "$SDK_BUILD" ]]; then
  xcrun swiftc \
    -target arm64-apple-macos13.0 \
    -o "$BUILD_DIR/VoiceForgeMenu" \
    "${SOURCES[@]}" \
    -framework AppKit \
    -framework ApplicationServices \
    -framework Carbon
else
  echo "当前 Swift compiler/SDK 不匹配（${COMPILER_BUILD} / ${SDK_BUILD}）。"
  echo "使用功能等价的 Objective-C 原生构建；Swift 源码已保留供工具链修复后重建。"
  xcrun clang \
    -fobjc-arc \
    -mmacosx-version-min=13.0 \
    -o "$BUILD_DIR/VoiceForgeMenu" \
    "$FALLBACK_SOURCE" \
    -framework AppKit \
    -framework ApplicationServices \
    -framework Carbon
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/VoiceForgeMenu" \
  "$APP_DIR/Contents/MacOS/VoiceForgeMenu"
cp "$SWIFT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

LOCAL_SIGNING_IDENTITY="VoiceForge Local Code Signing"
SIGNING_IDENTITY="${VOICEFORGE_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]] && security find-identity \
    -p codesigning "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null |
    grep -Fq "\"$LOCAL_SIGNING_IDENTITY\""; then
  SIGNING_IDENTITY="$LOCAL_SIGNING_IDENTITY"
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
BUNDLE_IDENTIFIER="$(
  /usr/libexec/PlistBuddy \
    -c "Print :CFBundleIdentifier" \
    "$APP_DIR/Contents/Info.plist"
)"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  # Keep the designated requirement stable across local rebuilds. Without an
  # explicit requirement, ad-hoc signing uses a changing cdhash and macOS TCC
  # treats every build as a new app, invalidating Accessibility permission.
  LOCAL_REQUIREMENT="=designated => identifier \"$BUNDLE_IDENTIFIER\""
  codesign \
    --force \
    --deep \
    --sign - \
    --requirements "$LOCAL_REQUIREMENT" \
    "$APP_DIR"
else
  codesign \
    --force \
    --deep \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR"
fi

mkdir -p "$HOME/Applications"
ditto "$APP_DIR" "$HOME/Applications/VoiceForge.app"
echo "VoiceForge.app 已构建并安装到 $HOME/Applications/VoiceForge.app"
