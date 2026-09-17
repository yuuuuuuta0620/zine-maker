#!/bin/bash
# SwiftPM の実行ファイルを .app バンドルに包む。
# Info.plist がないと NSOpenPanel やアクティベーションが正しく動かないため必須。
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

APP=".build/ZineMaker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/ZineMaker" "$APP/Contents/MacOS/ZineMaker"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ZineMaker</string>
  <key>CFBundleDisplayName</key><string>ZineMaker</string>
  <key>CFBundleIdentifier</key><string>com.zinemaker.app</string>
  <key>CFBundleExecutable</key><string>ZineMaker</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>ZineMaker Document</string>
      <key>CFBundleTypeExtensions</key><array><string>zine</string></array>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "built: $APP"
