#!/bin/sh
set -e
cd "$(dirname "$0")"
APP=Messenger.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -target arm64-apple-macos13 main.swift -o "$APP/Contents/MacOS/Messenger"
cp Info.plist "$APP/Contents/"
# Icon: AppIcon.png (từ make_icon.swift) -> AppIcon.icns, chỉ tạo khi chưa có
if [ ! -f AppIcon.icns ]; then
  [ -f AppIcon.png ] || swift make_icon.swift
  rm -rf AppIcon.iconset && mkdir AppIcon.iconset
  for s in 16 32 128 256 512; do
    sips -z $s $s AppIcon.png --out AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) AppIcon.png --out AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns AppIcon.iconset && rm -rf AppIcon.iconset
fi
mkdir -p "$APP/Contents/Resources" && cp AppIcon.icns "$APP/Contents/Resources/"
codesign --force -s - "$APP"
echo "OK: $(pwd)/$APP"
