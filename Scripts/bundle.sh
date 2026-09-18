#!/bin/bash
# SwiftPM の実行ファイルを .app バンドルに包む（CLI からの素早い確認用）。
# Info.plist は Xcode ビルドと共有している Resources/Info.plist を使う。
#
# 配布用の署名済みビルドは Xcode 側で作る:
#   xcodebuild -project zine-maker.xcodeproj -scheme ZineMaker -configuration Release build
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

APP=".build/ZineMaker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/ZineMaker" "$APP/Contents/MacOS/ZineMaker"

# Xcode のビルド変数を埋めて Info.plist を作る
sed -e 's|$(EXECUTABLE_NAME)|ZineMaker|g' \
    -e 's|$(PRODUCT_BUNDLE_IDENTIFIER)|com.zinemaker.app|g' \
    -e 's|$(MARKETING_VERSION)|0.1.0|g' \
    -e 's|$(CURRENT_PROJECT_VERSION)|1|g' \
    -e 's|$(MACOSX_DEPLOYMENT_TARGET)|14.0|g' \
    Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null

# アセットカタログをコンパイルしてアイコンを入れる
if command -v actool > /dev/null 2>&1; then
  actool Resources/Assets.xcassets \
    --compile "$APP/Contents/Resources" \
    --app-icon AppIcon --output-partial-info-plist /tmp/zm-icon.plist \
    --platform macosx --minimum-deployment-target 14.0 > /dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "built: $APP"
