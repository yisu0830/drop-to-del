#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
arch="${ARCH:-$(uname -m)}"
case "$arch" in
  arm64|x86_64) ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac

output="$root/build/$arch"
app="$output/Drop to Del.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc -O -parse-as-library -target "$arch-apple-macos14.0" \
  -module-cache-path "$output/module-cache" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  "$root"/源码/*.swift -o "$app/Contents/MacOS/DropToDel"
cp "$root/Assets/Info.plist" "$app/Contents/Info.plist"
cp "$root/Assets/Shredder.icns" "$app/Contents/Resources/Shredder.icns"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
ditto -c -k --keepParent "$app" "$output/Drop-to-Del-macOS-$arch.zip"
