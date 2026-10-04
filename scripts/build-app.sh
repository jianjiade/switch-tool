#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/switch-tool-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox -c release
bin=$(swift build --disable-sandbox -c release --show-bin-path)
app="$PWD/dist/Switch Tool.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/SwitchTool" "$app/Contents/MacOS/SwitchTool"
cp "$bin/SwitchHelper" "$app/Contents/Resources/SwitchHelper"
cp scripts/install-helper.sh "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.switchtool.app</string>
<key>CFBundleName</key><string>Switch Tool</string>
<key>CFBundleExecutable</key><string>SwitchTool</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app/Contents/Resources/SwitchHelper"
codesign --force --sign - "$app"
echo "$app"
