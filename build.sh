#!/usr/bin/env bash
# Manual build that bypasses `swift build` because the locally installed
# Command Line Tools cannot link the package manifest. Produces matched
# artifacts under .build/manual/ that mirror what SwiftPM would emit.
#
# Usage:
#   ./build.sh         # incremental rebuild of all three targets
#   ./build.sh run     # rebuild then launch the app
set -euo pipefail

cd "$(dirname "$0")"
OUT=.build/manual
mkdir -p "$OUT"

TARGET=arm64-apple-macosx14.0
SWIFT_VERSION=6

echo "Building GitKit..."
xcrun --sdk macosx swiftc \
  -target "$TARGET" \
  -swift-version "$SWIFT_VERSION" \
  -module-name GitKit \
  -emit-library -emit-module \
  -emit-module-path "$OUT/GitKit.swiftmodule" \
  -o "$OUT/libGitKit.dylib" \
  -Xlinker -install_name -Xlinker @rpath/libGitKit.dylib \
  $(find Sources/GitKit -name '*.swift' -type f)

# Weak-link FoundationModels (macOS 26+) when the SDK has it, so the app
# still launches on older macOS. Older SDKs build without it.
APPUI_LINK_FLAGS=()
if [[ -d "$(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/FoundationModels.framework" ]]; then
  APPUI_LINK_FLAGS=(-Xlinker -weak_framework -Xlinker FoundationModels)
fi

echo "Building AppUI..."
xcrun --sdk macosx swiftc \
  -target "$TARGET" \
  -swift-version "$SWIFT_VERSION" \
  -module-name AppUI \
  -emit-library -emit-module \
  -emit-module-path "$OUT/AppUI.swiftmodule" \
  -o "$OUT/libAppUI.dylib" \
  -I "$OUT" \
  -L "$OUT" -lGitKit \
  -Xlinker -install_name -Xlinker @rpath/libAppUI.dylib \
  ${APPUI_LINK_FLAGS[@]+"${APPUI_LINK_FLAGS[@]}"} \
  -Xlinker -rpath -Xlinker @loader_path \
  $(find Sources/AppUI -name '*.swift' -type f)

echo "Building AviApp..."
xcrun --sdk macosx swiftc \
  -target "$TARGET" \
  -swift-version "$SWIFT_VERSION" \
  -parse-as-library \
  -module-name AviApp \
  -o "$OUT/AviApp" \
  -I "$OUT" \
  -L "$OUT" -lAppUI -lGitKit \
  -Xlinker -rpath -Xlinker @executable_path \
  -Xlinker -rpath -Xlinker @loader_path \
  Sources/AviApp/AviApp.swift

echo "Built $OUT/AviApp"

if [[ "${1:-}" == "run" ]]; then
  exec "$OUT/AviApp"
fi
