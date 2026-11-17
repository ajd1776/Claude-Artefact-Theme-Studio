#!/bin/zsh
# Builds "Theme Studio.app" into ./build
# Usage: ./build.sh            (page source defaults to ../theme-studio.html)
#        WEB_SRC=path/to/page.html ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

WEB_SRC="${WEB_SRC:-../theme-studio.html}"
APP="build/Theme Studio.app"

echo "› compiling"
swift build -c release --arch arm64

echo "› assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ThemeStudio "$APP/Contents/MacOS/ThemeStudio"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/reference-template.html "$APP/Contents/Resources/reference-template.html"

# The page is written without a document skeleton (the Artifact host adds one), so add it here.
{
  printf '%s' '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>:root{color-scheme:light dark}body{margin:0}[hidden]{display:none!important}</style></head><body>'
  cat "$WEB_SRC"
  printf '%s' '</body></html>'
} > "$APP/Contents/Resources/index.html"

echo "› icon"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swift make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "› signing (ad hoc, this Mac only)"
codesign --force --deep --sign - "$APP"

echo "✓ built $APP"
